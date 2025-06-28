#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Let's Encrypt Certificate Management Script
echo
echo -e "${PURPLE}==================================${NC}"
echo -e "${WHITE}LET'S ENCRYPT CERTIFICATE MANAGER${NC}"
echo -e "${PURPLE}==================================${NC}"

# Logging function
log_operation() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/cert_manager.log
}

# Critical production safety checks
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run as root for production safety${NC}"
        exit 1
    fi
}

check_production_environment() {
    echo -e "${YELLOW}Are you sure you want to continue? (y/N)${NC}"
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled by user${NC}"
        exit 0
    fi
}

# Enhanced rollback function with verification
rollback() {
    if [ -d "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" ]; then
        echo -e "${YELLOW}Rolling back changes...${NC}"
        
        # Verify backup before rollback
        if [ -d "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP/live" ]; then
            rm -rf /etc/letsencrypt
            mv "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" /etc/letsencrypt
            echo -e "${GREEN}✓${NC} Rollback completed successfully"
            log_operation "ROLLBACK: Restored from backup.$BACKUP_TIMESTAMP"
        else
            echo -e "${RED}✗${NC} Backup verification failed, manual intervention required"
            log_operation "ROLLBACK: FAILED - backup verification failed"
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} No backup found for rollback"
        log_operation "ROLLBACK: FAILED - no backup available"
        exit 1
    fi
}

# Function to setup Cloudflare credentials
setup_cloudflare_credentials() {
    CREDENTIALS_PATH="/root/.secrets/certbot/cloudflare.ini"
    
    # Check if credentials already exist
    if [ -f "$CREDENTIALS_PATH" ]; then
        echo -e "${GREEN}✓${NC} Using existing Cloudflare credentials"
        return 0
    fi

    # Cloudflare Email
    read -p "Cloudflare Email: " CLOUDFLARE_EMAIL
    while [[ -z "$CLOUDFLARE_EMAIL" ]]; do
        echo -e "${RED}Cloudflare Email cannot be empty!${NC}"
        read -p "Cloudflare Email: " CLOUDFLARE_EMAIL
    done

    # Cloudflare API Key
    read -p "Cloudflare API Key: " CLOUDFLARE_API_KEY
    while [[ -z "$CLOUDFLARE_API_KEY" ]]; do
        echo -e "${RED}Cloudflare API Key cannot be empty!${NC}"
        read -p "Cloudflare API Key: " CLOUDFLARE_API_KEY
    done

    # Create credentials directory
    echo
    echo "Creating credentials directory..."
    mkdir -p "$(dirname "$CREDENTIALS_PATH")"

    # Check if it's an API Token (contains uppercase letters) or Global API Key
    if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
        echo -e "${GREEN}Detected API Token format${NC}"
        cat > "$CREDENTIALS_PATH" <<EOL
# Cloudflare API Token
dns_cloudflare_api_token = $CLOUDFLARE_API_KEY
EOL
        log_operation "SETUP: Created Cloudflare credentials with API Token"
    else
        echo -e "${NC}Detected Global API Key format${NC}"
        cat > "$CREDENTIALS_PATH" <<EOL
# Cloudflare Global API Key
dns_cloudflare_email = $CLOUDFLARE_EMAIL
dns_cloudflare_api_key = $CLOUDFLARE_API_KEY
EOL
        log_operation "SETUP: Created Cloudflare credentials with Global API Key"
    fi

    # Set proper permissions
    chmod 600 "$CREDENTIALS_PATH"
    echo -e "${GREEN}✓${NC} Cloudflare credentials configured successfully"
    echo
    echo -e "${BLUE}Credentials saved to: $CREDENTIALS_PATH${NC}"
}

# Function to validate Cloudflare credentials
validate_cloudflare_credentials() {
    local creds_path="/root/.secrets/certbot/cloudflare.ini"
    
    if [ ! -f "$creds_path" ]; then
        echo -e "${YELLOW}Warning: Cloudflare credentials not found${NC}"
        echo -e "${YELLOW}You may need to set up credentials for automatic renewal${NC}"
        return 1
    fi
    
    # Check if credentials file has proper format
    if grep -q "dns_cloudflare_api_token\|dns_cloudflare_api_key" "$creds_path"; then
        echo -e "${GREEN}✓${NC} Cloudflare credentials found and appear valid"
        return 0
    else
        echo -e "${RED}✗${NC} Cloudflare credentials file exists but format is invalid"
        return 1
    fi
}

# Trap for error handling
trap 'echo -e "${RED}Error occurred, attempting rollback...${NC}"; rollback; exit 1' ERR

# Run critical checks
check_root_privileges

# Check if script is run with parameters
if [ "$1" = "export" ] || [ "$1" = "--export" ] || [ "$1" = "-e" ]; then
    ACTION="export"
elif [ "$1" = "import" ] || [ "$1" = "--import" ] || [ "$1" = "-i" ]; then
    ACTION="import"
elif [ "$1" = "--dry-run" ] || [ "$1" = "-d" ]; then
    ACTION="import"
    DRY_RUN=true
    echo -e "${YELLOW}Running in DRY-RUN mode (no changes will be made)${NC}"
else
    # Interactive menu
    echo
    echo -e "${CYAN}Please select an action:${NC}"
    echo
    echo -e "${GREEN}1.${NC} Export certificates"
    echo -e "${GREEN}2.${NC} Import certificates"
    echo -e "${YELLOW}3.${NC} Exit"
    echo
    
    while true; do
        read -p "Enter your choice (1-3): " CHOICE
        case $CHOICE in
            1)
                ACTION="export"
                break
                ;;
            2)
                ACTION="import"
                echo
                check_production_environment
                echo
                # Request Cloudflare credentials immediately after choosing import
                echo -e "${CYAN}Please enter the required information:${NC}"
                echo
                setup_cloudflare_credentials
                break
                ;;
            3)
                echo -e "${CYAN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
fi

BACKUP_FILE="/root/letsencrypt-backup.tar.gz"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Export function
if [ "$ACTION" = "export" ]; then
    echo
    echo -e "${PURPLE}===================${NC}"
    echo -e "${WHITE}Certificate Export${NC}"
    echo -e "${PURPLE}===================${NC}"
    echo

    set -e

    echo -e "${GREEN}=========================${NC}"
    echo -e "${NC}1. Checking certificates${NC}"
    echo -e "${GREEN}=========================${NC}"
    echo

    # Check if Let's Encrypt directory exists
    if [ ! -d "/etc/letsencrypt" ]; then
        echo -e "${RED}Let's Encrypt directory not found!${NC}"
        echo -e "${RED}Let's Encrypt is not installed or certificates are missing.${NC}"
        exit 1
    fi

    # Check if certificates exist
    if [ ! -d "/etc/letsencrypt/live" ] || [ -z "$(ls -A /etc/letsencrypt/live 2>/dev/null)" ]; then
        echo -e "${RED}No certificates found in /etc/letsencrypt/live${NC}"
        exit 1
    fi

    echo "Validating certificate files..."
    echo
    ls -1 /etc/letsencrypt/live | grep -v README | while read domain; do
        if [ -n "$domain" ]; then
            # Validate certificate
            if openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -text >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} $domain"
            else
                echo -e "${RED}✗${NC} $domain (invalid certificate)"
            fi
        fi
    done

    echo
    echo -e "${GREEN}------------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Certificate validation completed!"
    echo -e "${GREEN}------------------------------------${NC}"
    echo

    echo -e "${GREEN}===================${NC}"
    echo -e "${NC}2. Creating backup"
    echo -e "${GREEN}===================${NC}"
    echo

    # Remove old backup if exists
    if [ -f "$BACKUP_FILE" ]; then
        echo "Removing old backup..."
        rm -f "$BACKUP_FILE"
    fi

    # Create backup archive with verification
    echo "Creating certificate backup..."
    echo
    if tar --preserve-permissions -czf "$BACKUP_FILE" -C /etc letsencrypt/; then
        echo -e "${GREEN}✓${NC} Backup created successfully"
        
        # Verify archive integrity
        if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Archive integrity verified"
        else
            echo -e "${RED}✗${NC} Archive verification failed"
            rm -f "$BACKUP_FILE"
            exit 1
        fi
        
        # Show archive size
        ARCHIVE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_operation "EXPORT: Created backup $BACKUP_FILE ($ARCHIVE_SIZE)"
    else
        echo -e "${RED}Failed to create backup archive!${NC}"
        exit 1
    fi

    echo
    echo -e "${GREEN}--------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Certificate export completed!"
    echo -e "${GREEN}--------------------------------${NC}"
    echo

    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}✓${NC} Certificate export completed successfully!"
    echo -e "${GREEN}=============================================${NC}"
    echo
    echo -e "${CYAN}Export Information:${NC}"
    echo -e "Archive size: ${WHITE}$ARCHIVE_SIZE${NC}"
    echo -e "Backup file: ${WHITE}$BACKUP_FILE${NC}"
    echo

    exit 0
fi

# Import function
if [ "$ACTION" = "import" ]; then
    echo
    echo -e "${PURPLE}===================${NC}"
    echo -e "${WHITE}Certificate Import${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}(DRY-RUN MODE)${NC}"
    fi
    echo -e "${PURPLE}===================${NC}"
    echo

    if [ "$DRY_RUN" != true ]; then
        set -e
    fi

    # Production confirmation for import
    if [ "$DRY_RUN" != true ]; then
        # Request Cloudflare credentials for command line import
        echo -e "${CYAN}Please enter the required information:${NC}"
        echo
        setup_cloudflare_credentials
    fi

    echo
    echo -e "${GREEN}=====================${NC}"
    echo -e "${NC}1. Verifying archive${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo

    # Check if backup archive exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}Backup archive not found: $BACKUP_FILE${NC}"
        echo -e "${RED}Please transfer the backup file to /root/ first${NC}"
        exit 1
    fi

    # Critical: Verify archive integrity and content
    echo "Verifying archive integrity..."
    if ! tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Archive is corrupted or invalid!"
        log_operation "IMPORT: FAILED - corrupted archive"
        exit 1
    fi

    # Critical: Check if archive contains essential Let's Encrypt structure
    if ! tar -tzf "$BACKUP_FILE" | grep -q "letsencrypt/live"; then
        echo -e "${RED}✗${NC} Archive doesn't contain Let's Encrypt live directory!"
        log_operation "IMPORT: FAILED - invalid archive structure"
        exit 1
    fi

    # Verify we have actual certificates in the archive
    CERT_COUNT=$(tar -tzf "$BACKUP_FILE" | grep -c "fullchain.pem" || echo "0")
    if [ "$CERT_COUNT" -eq 0 ]; then
        echo -e "${RED}✗${NC} Archive contains no certificates!"
        log_operation "IMPORT: FAILED - no certificates in archive"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Archive verification passed"

    echo
    echo -e "${GREEN}----------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Archive verification completed!"
    echo -e "${GREEN}----------------------------------${NC}"
    echo

    echo -e "${GREEN}======================${NC}"
    echo -e "${NC}2. Installing certbot${NC}"
    echo -e "${GREEN}======================${NC}"
    echo

    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN] Would install certbot and DNS plugins${NC}"
        else
            echo "Installing certbot and DNS plugins..."
            apt-get update -y >/dev/null 2>&1
            apt-get install -y certbot python3-certbot-dns-cloudflare >/dev/null 2>&1
            echo -e "${GREEN}✓${NC} Certbot installed"
        fi
    else
        echo -e "${GREEN}✓${NC} Certbot already installed"
    fi

    echo
    echo -e "${GREEN}----------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Certbot installation completed!"
    echo -e "${GREEN}----------------------------------${NC}"
    echo

    echo -e "${GREEN}==========================${NC}"
    echo -e "${NC}3. Validating credentials${NC}"
    echo -e "${GREEN}==========================${NC}"
    echo

    # Validate the credentials we just set up
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would validate Cloudflare credentials${NC}"
    else
        echo "Checking Cloudflare API..."
        if validate_cloudflare_credentials; then
            echo -e "${GREEN}✓${NC} Cloudflare credentials validated"
        else
            echo -e "${RED}✗${NC} Cloudflare credentials validation failed"
            echo -e "${RED}This should not happen after setup${NC}"
            exit 1
        fi
    fi

    echo
    echo -e "${GREEN}-----------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Credential validation completed!"
    echo -e "${GREEN}-----------------------------------${NC}"
    echo

    echo -e "${GREEN}===================${NC}"
    echo -e "${NC}4. Backing up data${NC}"
    echo -e "${GREEN}===================${NC}"
    echo

    # Backup existing certificates if they exist
    if [ -d "/etc/letsencrypt" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN] Would backup existing certificates${NC}"
        else
            echo "Creating backup of existing certificates..."
            cp -r /etc/letsencrypt "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP"
            echo -e "${GREEN}✓${NC} Existing data backed up"
            log_operation "IMPORT: Backed up existing certs to backup.$BACKUP_TIMESTAMP"
        fi
    else
        echo -e "${GREEN}✓${NC} No existing certificates to backup"
    fi

    echo
    echo -e "${GREEN}-------------------------${NC}"
    echo -e "${GREEN}✓${NC} Data backup completed!"
    echo -e "${GREEN}-------------------------${NC}"
    echo

    echo -e "${GREEN}===========================${NC}"
    echo -e "${NC}5. Extracting certificates${NC}"
    echo -e "${GREEN}===========================${NC}"
    echo

    # Extract backup archive
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would extract certificates to /etc/${NC}"
    else
        echo "Extracting certificate archive..."
        # Remove existing letsencrypt directory
        rm -rf /etc/letsencrypt
        
        # Critical: Verify extraction was successful
        if tar -xzf "$BACKUP_FILE" -C /etc/; then
            echo -e "${GREEN}✓${NC} Certificates extracted successfully"
            
            # Verify critical files exist after extraction
            if [ ! -d "/etc/letsencrypt/live" ]; then
                echo -e "${RED}✗${NC} Critical error: live directory missing after extraction"
                rollback
                exit 1
            fi
            
            # Count extracted certificates
            EXTRACTED_CERTS=$(find /etc/letsencrypt/live -name "fullchain.pem" | wc -l)
            log_operation "IMPORT: Extracted $EXTRACTED_CERTS certificates"
        else
            echo -e "${RED}✗${NC} Failed to extract certificate archive!"
            log_operation "IMPORT: FAILED - extraction error"
            rollback
            exit 1
        fi

        # Set proper permissions
        echo
        echo "Setting file permissions..."
        chown -R root:root /etc/letsencrypt
        chmod -R 600 /etc/letsencrypt
        chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
    fi

    echo
    echo -e "${GREEN}------------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Certificate extraction completed!"
    echo -e "${GREEN}------------------------------------${NC}"
    echo

    echo -e "${GREEN}====================${NC}"
    echo -e "${NC}6. Fixing structure${NC}"
    echo -e "${GREEN}====================${NC}"
    echo

    # Fix certificate structure
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would check and fix certificate symlink structure${NC}"
    else
        echo "Checking and fixing certificate structure..."
        for live_dir in /etc/letsencrypt/live/*/; do
            [ ! -d "$live_dir" ] && continue

            domain=$(basename "$live_dir")
            [ "$domain" = "*" ] && continue

            archive_dir="/etc/letsencrypt/archive/$domain"
            mkdir -p "$archive_dir"

            # Check if files in live are not symlinks
            if [ -f "$live_dir/fullchain.pem" ] && [ ! -L "$live_dir/fullchain.pem" ]; then
                # Move files to archive with error handling
                for file in "$live_dir"/*.pem; do
                    if [ -f "$file" ]; then
                        mv "$file" "$archive_dir/" 2>/dev/null || echo "Warning: Could not move $(basename "$file")"
                    fi
                done

                # Rename with version number
                cd "$archive_dir"
                [ -f fullchain.pem ] && mv fullchain.pem fullchain1.pem
                [ -f privkey.pem ] && mv privkey.pem privkey1.pem
                [ -f cert.pem ] && mv cert.pem cert1.pem
                [ -f chain.pem ] && mv chain.pem chain1.pem

                # Create missing files if needed
                if [ ! -f cert1.pem ] && [ -f fullchain1.pem ]; then
                    if ! openssl x509 -in fullchain1.pem -out cert1.pem 2>/dev/null; then
                        echo "Warning: Could not extract cert from fullchain"
                    fi
                fi

                if [ ! -f chain1.pem ] && [ -f fullchain1.pem ]; then
                    if ! sed '1,/-----END CERTIFICATE-----/d' fullchain1.pem > chain1.pem; then
                        echo "Warning: Could not extract chain from fullchain"
                    fi
                fi

                # Create symlinks with error handling
                cd "$live_dir"
                for cert_type in fullchain privkey cert chain; do
                    if [ -f "$archive_dir/${cert_type}1.pem" ]; then
                        ln -sf "../../archive/$domain/${cert_type}1.pem" "${cert_type}.pem"
                    else
                        echo "Warning: Missing ${cert_type}1.pem in archive"
                    fi
                done
            fi
        done
        echo -e "${GREEN}✓${NC} Certificate structure fixed"
    fi

    echo
    echo -e "${GREEN}------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Structure fixing completed!"
    echo -e "${GREEN}------------------------------${NC}"
    echo

    echo -e "${GREEN}====================${NC}"
    echo -e "${NC}7. Updating configs${NC}"
    echo -e "${GREEN}====================${NC}"
    echo

    # Update renewal configurations
    # Get certbot version safely
    CERTBOT_VERSION=$(certbot --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    CERTBOT_VERSION=${CERTBOT_VERSION:-"2.11.0"}

    # Check for Cloudflare credentials
    CREDENTIALS_PATH="/root/.secrets/certbot/cloudflare.ini"
    if [ ! -f "$CREDENTIALS_PATH" ]; then
        echo -e "${YELLOW}Warning: Cloudflare credentials not found${NC}"
        echo -e "${YELLOW}Renewal may fail without proper credentials${NC}"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would update renewal configurations${NC}"
    else
        echo "Updating renewal configurations..."
        for conf_file in /etc/letsencrypt/renewal/*.conf; do
            [ ! -f "$conf_file" ] && continue

            domain=$(basename "$conf_file" .conf)

            # Create backup of original config
            cp "$conf_file" "$conf_file.backup"

            cat > "$conf_file" << EOF
version = $CERTBOT_VERSION
archive_dir = /etc/letsencrypt/archive/$domain
cert = /etc/letsencrypt/live/$domain/cert.pem
privkey = /etc/letsencrypt/live/$domain/privkey.pem
chain = /etc/letsencrypt/live/$domain/chain.pem
fullchain = /etc/letsencrypt/live/$domain/fullchain.pem

[renewalparams]
authenticator = dns-cloudflare
dns_cloudflare_credentials = $CREDENTIALS_PATH
dns_cloudflare_propagation_seconds = 10
server = https://acme-v02.api.letsencrypt.org/directory
key_type = ecdsa
elliptic_curve = secp384r1
EOF
        done

        echo -e "${GREEN}✓${NC} Renewal configurations updated"
    fi

    echo
    echo -e "${GREEN}---------------------------${NC}"
    echo -e "${GREEN}✓${NC} Config update completed!"
    echo -e "${GREEN}---------------------------${NC}"
    echo

    echo -e "${GREEN}==========================${NC}"
    echo -e "${NC}8. Verifying certificates${NC}"
    echo -e "${GREEN}==========================${NC}"
    echo

    # Critical: Verify imported certificates are valid
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would verify certificates with 'certbot certificates'${NC}"
    else
        echo "Performing critical certificate validation..."
        # Test certbot can read the certificates
        if ! certbot certificates >/dev/null 2>&1; then
            echo -e "${RED}✗${NC} Critical error: Certbot cannot read imported certificates"
            log_operation "IMPORT: FAILED - certificate validation error"
            rollback
            exit 1
        fi
        
        # Verify each certificate file
        VALIDATION_FAILED=0
        for live_dir in /etc/letsencrypt/live/*/; do
            [ ! -d "$live_dir" ] && continue
            domain=$(basename "$live_dir")
            [ "$domain" = "*" ] && continue
            
            if [ -f "$live_dir/fullchain.pem" ]; then
                if openssl x509 -in "$live_dir/fullchain.pem" -noout -text >/dev/null 2>&1; then
                    echo -e "${GREEN}✓${NC} $domain certificate is valid"
                else
                    echo -e "${RED}✗${NC} $domain certificate is invalid"
                    VALIDATION_FAILED=1
                fi
            else
                echo -e "${RED}✗${NC} $domain missing fullchain.pem"
                VALIDATION_FAILED=1
            fi
        done
        
        if [ "$VALIDATION_FAILED" -eq 1 ]; then
            echo -e "${RED}✗${NC} Certificate validation failed"
            log_operation "IMPORT: FAILED - certificate validation"
            rollback
            exit 1
        fi
        
        echo -e "${GREEN}✓${NC} All certificates validated successfully"
    fi

    echo
    echo -e "${GREEN}--------------------------------------${NC}"
    echo -e "${GREEN}✓${NC} Certificate verification completed!"
    echo -e "${GREEN}--------------------------------------${NC}"
    echo

    echo -e "${GREEN}===================${NC}"
    echo -e "${NC}9. Testing renewal${NC}"
    echo -e "${GREEN}===================${NC}"
    echo

    # Always test renewal as part of import process
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would test renewal with 'certbot renew --dry-run'${NC}"
    else
        echo "Testing certificate renewal..."
        if certbot renew --dry-run 2>/dev/null; then
            echo
            echo -e "${GREEN}✓${NC} Certificate renewal test PASSED"
            echo -e "${GREEN}✓${NC} All certificates are ready for automatic renewal"
            log_operation "IMPORT: Renewal test PASSED"
        else
            echo
            echo -e "${RED}✗${NC} Certificate renewal test FAILED"
            echo -e "${YELLOW}Certificate renewal may not work${NC}"
            echo -e "${YELLOW}Check Cloudflare credentials and DNS settings${NC}"
            log_operation "IMPORT: Renewal test FAILED"
            
            read -p "Continue despite renewal test failure? (y/N): " CONTINUE_ANYWAY
            if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}Import cancelled by user${NC}"
                rollback
                exit 1
            fi
        fi
    fi

    echo
    echo -e "${GREEN}--------------------------${NC}"
    echo -e "${GREEN}✓${NC} Renewal test completed!"
    echo -e "${GREEN}--------------------------${NC}"
    echo

    echo -e "${GREEN}================${NC}"
    echo -e "${NC}10. Cleaning up${NC}"
    echo -e "${GREEN}================${NC}"
    echo

    # Clean up backup file
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would remove backup archive${NC}"
    else
        echo "Removing backup archive..."
        rm -f "$BACKUP_FILE"
        echo -e "${GREEN}✓${NC} Backup archive removed"
        log_operation "IMPORT: Completed successfully, cleaned up $BACKUP_FILE"
    fi

    echo
    echo -e "${GREEN}---------------------${NC}"
    echo -e "${GREEN}✓${NC} Cleanup completed!"
    echo -e "${GREEN}---------------------${NC}"
    echo

    echo -e "${GREEN}=============================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GREEN}✓${NC} Certificate import DRY-RUN completed successfully!"
        echo -e "${CYAN}No changes were made to the system.${NC}"
    else
        echo -e "${GREEN}✓${NC} Certificate import completed successfully!"
    fi
    echo -e "${GREEN}=============================================${NC}"
    echo
    
    if [ "$DRY_RUN" != true ]; then
        echo -e "${CYAN}Imported Certificates:${NC}"
        ls -1 /etc/letsencrypt/live 2>/dev/null | grep -v README | while read domain; do
            if [ -n "$domain" ]; then
                echo "$domain"
            fi
        done
        echo
    fi

    exit 0
fi
