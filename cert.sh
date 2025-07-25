#!/bin/bash

#==============================
# LET'S ENCRYPT CERTIFICATE MANAGER
#==============================

# Color constants
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Status symbols
readonly CHECK="✓"
readonly CROSS="✗"
readonly WARNING="!"
readonly INFO="*"
readonly ARROW="→"

# Global variables
BACKUP_FILE="/root/letsencrypt-backup.tar.gz"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CREDENTIALS_PATH="/root/.secrets/certbot/cloudflare.ini"
ACTION=""
DRY_RUN=false

#======================
# VALIDATION FUNCTIONS
#======================

# Check root privileges
check_root_privileges() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${CROSS}${NC} This script must be run as root for production safety"
        echo
        exit 1
    fi
}

# Command execution check
check_command() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}${CROSS}${NC} Error: $1"
        echo
        exit 1
    fi
}

# Check production environment
check_production_environment() {
    echo -ne "${YELLOW}Are you sure you want to continue? (y/N): ${NC}"
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled by user${NC}"
        echo
        exit 0
    fi
}

#====================
# MAIN MENU FUNCTIONS
#====================

# Display main menu
show_main_menu() {
    echo
    echo -e "${PURPLE}==========================${NC}"
    echo -e "${WHITE}LET'S ENCRYPT CERTIFICATE${NC}"
    echo -e "${PURPLE}==========================${NC}"
    echo
    echo -e "${CYAN}Please select an action:${NC}"
    echo
    echo -e "${GREEN}1.${NC} Export certificates"
    echo -e "${GREEN}2.${NC} Import certificates"
    echo -e "${YELLOW}3.${NC} Exit"
    echo
}

# Handle user choice
handle_user_choice() {
    local choice=$1
    
    case $choice in
        1)
            ACTION="export"
            ;;
        2)
            ACTION="import"
            echo
            check_production_environment
            echo
            setup_cloudflare_credentials
            ;;
        3)
            echo -e "${CYAN}Goodbye!${NC}"
            echo
            exit 0
            ;;
        *)
            echo -e "${RED}${CROSS}${NC} Invalid choice. Please enter 1, 2, or 3."
            echo
            exit 1
            ;;
    esac
}

#=====================================
# CLOUDFLARE CREDENTIAL FUNCTIONS
#=====================================

# Input Cloudflare email
input_cloudflare_email() {
    echo -ne "${CYAN}Cloudflare Email: ${NC}"
    read CLOUDFLARE_EMAIL
    while [[ -z "$CLOUDFLARE_EMAIL" ]]; do
        echo -e "${RED}${CROSS}${NC} Cloudflare Email cannot be empty!"
        echo
        echo -ne "${CYAN}Cloudflare Email: ${NC}"
        read CLOUDFLARE_EMAIL
    done
}

# Input Cloudflare API key
input_cloudflare_api_key() {
    echo -ne "${CYAN}Cloudflare API Key: ${NC}"
    read CLOUDFLARE_API_KEY
    while [[ -z "$CLOUDFLARE_API_KEY" ]]; do
        echo -e "${RED}${CROSS}${NC} Cloudflare API Key cannot be empty!"
        echo
        echo -ne "${CYAN}Cloudflare API Key: ${NC}"
        read CLOUDFLARE_API_KEY
    done
}

# Setup Cloudflare credentials
setup_cloudflare_credentials() {
    if [ -f "$CREDENTIALS_PATH" ]; then
        return 0
    fi

    input_cloudflare_email
    input_cloudflare_api_key

    echo
    echo -e "${CYAN}${INFO}${NC} Setting up Cloudflare credentials..."
    echo -e "${GRAY}  ${ARROW}${NC} Creating credentials directory"
    mkdir -p "$(dirname "$CREDENTIALS_PATH")"

    if [[ $CLOUDFLARE_API_KEY =~ [A-Z] ]]; then
        echo -e "${GRAY}  ${ARROW}${NC} Detected API Token format"
        create_api_token_credentials
    else
        echo -e "${GRAY}  ${ARROW}${NC} Detected Global API Key format"
        create_global_key_credentials
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Setting proper permissions"
    chmod 600 "$CREDENTIALS_PATH"
    echo -e "${GREEN}${CHECK}${NC} Cloudflare credentials configured successfully!"
    echo
    echo -e "${BLUE}Credentials saved to: $CREDENTIALS_PATH${NC}"
    log_operation "SETUP: Created Cloudflare credentials"
}

# Create API token credentials
create_api_token_credentials() {
    cat > "$CREDENTIALS_PATH" <<EOL
# Cloudflare API Token
dns_cloudflare_api_token = $CLOUDFLARE_API_KEY
EOL
    log_operation "SETUP: Created Cloudflare credentials with API Token"
}

# Create global key credentials
create_global_key_credentials() {
    cat > "$CREDENTIALS_PATH" <<EOL
# Cloudflare Global API Key
dns_cloudflare_email = $CLOUDFLARE_EMAIL
dns_cloudflare_api_key = $CLOUDFLARE_API_KEY
EOL
    log_operation "SETUP: Created Cloudflare credentials with Global API Key"
}

# Validate Cloudflare credentials
validate_cloudflare_credentials() {
    if [ ! -f "$CREDENTIALS_PATH" ]; then
        echo -e "${YELLOW}${WARNING}${NC} Cloudflare credentials not found"
        echo -e "${YELLOW}You may need to set up credentials for automatic renewal${NC}"
        return 1
    fi
    
    if grep -q "dns_cloudflare_api_token\|dns_cloudflare_api_key" "$CREDENTIALS_PATH"; then
        return 0
    else
        echo -e "${RED}${CROSS}${NC} Cloudflare credentials file exists but format is invalid"
        return 1
    fi
}

#=============================
# LOGGING AND ROLLBACK FUNCTIONS
#=============================

# Logging function
log_operation() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/cert_manager.log
}

# Enhanced rollback function with verification
rollback() {
    if [ -d "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" ]; then
        echo -e "${YELLOW}${WARNING}${NC} Rolling back changes..."
        
        echo -e "${GRAY}  ${ARROW}${NC} Verifying backup integrity"
        if [ -d "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP/live" ]; then
            echo -e "${GRAY}  ${ARROW}${NC} Removing current installation"
            rm -rf /etc/letsencrypt
            echo -e "${GRAY}  ${ARROW}${NC} Restoring from backup"
            mv "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" /etc/letsencrypt
            echo -e "${GREEN}${CHECK}${NC} Rollback completed successfully!"
            log_operation "ROLLBACK: Restored from backup.$BACKUP_TIMESTAMP"
        else
            echo -e "${RED}${CROSS}${NC} Backup verification failed, manual intervention required"
            echo
            log_operation "ROLLBACK: FAILED - backup verification failed"
            exit 1
        fi
    else
        echo -e "${RED}${CROSS}${NC} No backup found for rollback"
        echo
        log_operation "ROLLBACK: FAILED - no backup available"
        exit 1
    fi
}

#==============================
# CERTIFICATE EXPORT FUNCTIONS
#==============================

# Validate existing certificates
validate_existing_certificates() {
    echo -e "${CYAN}${INFO}${NC} Validating existing certificates..."
    echo -e "${GRAY}  ${ARROW}${NC} Checking Let's Encrypt directory existence"
    if [ ! -d "/etc/letsencrypt" ]; then
        echo -e "${RED}${CROSS}${NC} Let's Encrypt directory not found!"
        echo -e "${RED}Let's Encrypt is not installed or certificates are missing.${NC}"
        echo
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Checking for certificate files"
    if [ ! -d "/etc/letsencrypt/live" ] || [ -z "$(ls -A /etc/letsencrypt/live 2>/dev/null)" ]; then
        echo -e "${RED}${CROSS}${NC} No certificates found in /etc/letsencrypt/live"
        echo
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Validating certificate integrity"
    validate_certificate_files
    echo -e "${GREEN}${CHECK}${NC} Certificate validation completed successfully!"
}

# Validate certificate files
validate_certificate_files() {
    ls -1 /etc/letsencrypt/live | grep -v README | while read domain; do
        if [ -n "$domain" ]; then
            if ! openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -text >/dev/null 2>&1; then
                echo -e "${RED}${CROSS}${NC} $domain - invalid certificate"
            fi
        fi
    done
}

# Create backup archive
create_backup_archive() {
    echo -e "${CYAN}${INFO}${NC} Creating certificate backup archive..."
    echo -e "${GRAY}  ${ARROW}${NC} Removing old backup if exists"
    if [ -f "$BACKUP_FILE" ]; then
        rm -f "$BACKUP_FILE"
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Creating new backup archive"
    tar --preserve-permissions -czf "$BACKUP_FILE" -C /etc letsencrypt/
    check_command "Failed to create backup archive"

    echo -e "${GRAY}  ${ARROW}${NC} Verifying archive integrity"
    tar -tzf "$BACKUP_FILE" >/dev/null 2>&1
    check_command "Archive verification failed"

    echo -e "${GRAY}  ${ARROW}${NC} Calculating archive size"
    ARCHIVE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GRAY}  ${ARROW}${NC} Archive size: $ARCHIVE_SIZE"
    log_operation "EXPORT: Created backup $BACKUP_FILE ($ARCHIVE_SIZE)"
    echo -e "${GREEN}${CHECK}${NC} Backup archive created successfully!"
}

# Display export completion info
display_export_completion_info() {
    echo
    echo -e "${PURPLE}====================${NC}"
    echo -e "${GREEN}${CHECK}${NC} EXPORT COMPLETED!"
    echo -e "${PURPLE}====================${NC}"
    echo
    echo -e "${CYAN}Export Information:${NC}"
    echo -e "${WHITE}• Archive size: $ARCHIVE_SIZE${NC}"
    echo -e "${WHITE}• Backup file: $BACKUP_FILE${NC}"
}

#==============================
# CERTIFICATE IMPORT FUNCTIONS
#==============================

# Verify archive integrity
verify_archive_integrity() {
    echo -e "${CYAN}${INFO}${NC} Verifying archive integrity and content..."
    echo -e "${GRAY}  ${ARROW}${NC} Checking backup file existence"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}${CROSS}${NC} Backup archive not found: $BACKUP_FILE"
        echo -e "${RED}Please transfer the backup file to /root/ first${NC}"
        echo
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Verifying archive integrity"
    if ! tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        echo -e "${RED}${CROSS}${NC} Archive is corrupted or invalid!"
        echo
        log_operation "IMPORT: FAILED - corrupted archive"
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Checking Let's Encrypt structure"
    if ! tar -tzf "$BACKUP_FILE" | grep -q "letsencrypt/live"; then
        echo -e "${RED}${CROSS}${NC} Archive doesn't contain Let's Encrypt live directory!"
        echo
        log_operation "IMPORT: FAILED - invalid archive structure"
        exit 1
    fi

    echo -e "${GRAY}  ${ARROW}${NC} Verifying certificate content"
    CERT_COUNT=$(tar -tzf "$BACKUP_FILE" | grep -c "fullchain.pem" || echo "0")
    if [ "$CERT_COUNT" -eq 0 ]; then
        echo -e "${RED}${CROSS}${NC} Archive contains no certificates!"
        echo
        log_operation "IMPORT: FAILED - no certificates in archive"
        exit 1
    fi
    echo -e "${GREEN}${CHECK}${NC} Archive verification completed successfully!"
}

# Install certbot package
install_certbot_package() {
    echo -e "${CYAN}${INFO}${NC} Installing certbot and DNS plugins..."
    echo -e "${GRAY}  ${ARROW}${NC} Updating package repositories"
    apt-get update -y >/dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Installing certbot and python3-certbot-dns-cloudflare"
    apt-get install -y certbot python3-certbot-dns-cloudflare >/dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Certbot installation completed!"
}

# Validate credentials for import
validate_import_credentials() {
    echo -e "${CYAN}${INFO}${NC} Validating Cloudflare credentials..."
    echo -e "${GRAY}  ${ARROW}${NC} Checking API connectivity"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would validate Cloudflare credentials${NC}"
    else
        if validate_cloudflare_credentials; then
            echo -e "${GREEN}${CHECK}${NC} Cloudflare credentials validated successfully!"
        else
            echo -e "${RED}${CROSS}${NC} Cloudflare credentials validation failed"
            echo -e "${RED}This should not happen after setup${NC}"
            echo
            exit 1
        fi
    fi
}

# Backup existing data
backup_existing_data() {
    echo -e "${CYAN}${INFO}${NC} Backing up existing certificate data..."
    if [ -d "/etc/letsencrypt" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN] Would backup existing certificates${NC}"
        else
            echo -e "${GRAY}  ${ARROW}${NC} Creating backup of existing certificates"
            cp -r /etc/letsencrypt "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP"
            echo -e "${GRAY}  ${ARROW}${NC} Backup created at /etc/letsencrypt.backup.$BACKUP_TIMESTAMP"
            log_operation "IMPORT: Backed up existing certs to backup.$BACKUP_TIMESTAMP"
        fi
        echo -e "${GREEN}${CHECK}${NC} Existing data backup completed!"
    else
        echo -e "${GREEN}${CHECK}${NC} No existing certificates to backup"
    fi
}

# Extract certificate archive
extract_certificate_archive() {
    echo -e "${CYAN}${INFO}${NC} Extracting certificate archive..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would extract certificates to /etc/${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Removing existing letsencrypt directory"
        rm -rf /etc/letsencrypt
        
        echo -e "${GRAY}  ${ARROW}${NC} Extracting certificates"
        tar -xzf "$BACKUP_FILE" -C /etc/
        check_command "Failed to extract certificate archive"
        
        echo -e "${GRAY}  ${ARROW}${NC} Verifying extraction results"
        if [ ! -d "/etc/letsencrypt/live" ]; then
            echo -e "${RED}${CROSS}${NC} Critical error: live directory missing after extraction"
            echo
            rollback
            exit 1
        fi
        
        echo -e "${GRAY}  ${ARROW}${NC} Counting extracted certificates"
        EXTRACTED_CERTS=$(find /etc/letsencrypt/live -name "fullchain.pem" | wc -l)
        echo -e "${GRAY}  ${ARROW}${NC} Extracted $EXTRACTED_CERTS certificates"
        
        echo -e "${GRAY}  ${ARROW}${NC} Setting file permissions"
        set_certificate_permissions
        log_operation "IMPORT: Extracted $EXTRACTED_CERTS certificates"
    fi
    echo -e "${GREEN}${CHECK}${NC} Certificate extraction completed!"
}

# Set certificate permissions
set_certificate_permissions() {
    chown -R root:root /etc/letsencrypt
    chmod -R 600 /etc/letsencrypt
    chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
}

# Fix certificate structure
fix_certificate_structure() {
    echo -e "${CYAN}${INFO}${NC} Checking and fixing certificate structure..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would check and fix certificate symlink structure${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Scanning certificate directories"
        for live_dir in /etc/letsencrypt/live/*/; do
            [ ! -d "$live_dir" ] && continue
            
            domain=$(basename "$live_dir")
            [ "$domain" = "*" ] && continue
            
            echo -e "${GRAY}  ${ARROW}${NC} Processing $domain certificates"
            fix_domain_structure "$domain" "$live_dir"
        done
    fi
    echo -e "${GREEN}${CHECK}${NC} Certificate structure verification completed!"
}

# Fix domain structure
fix_domain_structure() {
    local domain=$1
    local live_dir=$2
    local archive_dir="/etc/letsencrypt/archive/$domain"
    
    mkdir -p "$archive_dir"
    
    if [ -f "$live_dir/fullchain.pem" ] && [ ! -L "$live_dir/fullchain.pem" ]; then
        echo -e "${GRAY}  ${ARROW}${NC} Fixing structure for $domain"
        
        move_files_to_archive "$live_dir" "$archive_dir"
        rename_files_with_version "$archive_dir"
        create_missing_files "$archive_dir"
        create_symlinks "$live_dir" "$archive_dir" "$domain"
    fi
}

# Move files to archive
move_files_to_archive() {
    local live_dir=$1
    local archive_dir=$2
    
    for file in "$live_dir"/*.pem; do
        if [ -f "$file" ]; then
            mv "$file" "$archive_dir/" 2>/dev/null || echo "Warning: Could not move $(basename "$file")"
        fi
    done
}

# Rename files with version
rename_files_with_version() {
    local archive_dir=$1
    
    cd "$archive_dir"
    [ -f fullchain.pem ] && mv fullchain.pem fullchain1.pem
    [ -f privkey.pem ] && mv privkey.pem privkey1.pem
    [ -f cert.pem ] && mv cert.pem cert1.pem
    [ -f chain.pem ] && mv chain.pem chain1.pem
}

# Create missing files
create_missing_files() {
    local archive_dir=$1
    
    if [ ! -f "$archive_dir/cert1.pem" ] && [ -f "$archive_dir/fullchain1.pem" ]; then
        openssl x509 -in "$archive_dir/fullchain1.pem" -out "$archive_dir/cert1.pem" 2>/dev/null || echo "Warning: Could not extract cert from fullchain"
    fi
    
    if [ ! -f "$archive_dir/chain1.pem" ] && [ -f "$archive_dir/fullchain1.pem" ]; then
        sed '1,/-----END CERTIFICATE-----/d' "$archive_dir/fullchain1.pem" > "$archive_dir/chain1.pem" || echo "Warning: Could not extract chain from fullchain"
    fi
}

# Create symlinks
create_symlinks() {
    local live_dir=$1
    local archive_dir=$2
    local domain=$3
    
    cd "$live_dir"
    for cert_type in fullchain privkey cert chain; do
        if [ -f "$archive_dir/${cert_type}1.pem" ]; then
            ln -sf "../../archive/$domain/${cert_type}1.pem" "${cert_type}.pem"
        else
            echo "Warning: Missing ${cert_type}1.pem in archive"
        fi
    done
}

# Update renewal configurations
update_renewal_configurations() {
    echo -e "${CYAN}${INFO}${NC} Updating renewal configurations..."
    local certbot_version=$(certbot --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    certbot_version=${certbot_version:-"2.11.0"}
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would update renewal configurations${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Processing renewal configuration files"
        for conf_file in /etc/letsencrypt/renewal/*.conf; do
            [ ! -f "$conf_file" ] && continue
            
            domain=$(basename "$conf_file" .conf)
            echo -e "${GRAY}  ${ARROW}${NC} Updating configuration for $domain"
            
            create_renewal_config "$conf_file" "$domain" "$certbot_version"
        done
    fi
    echo -e "${GREEN}${CHECK}${NC} Renewal configurations updated successfully!"
}

# Create renewal config
create_renewal_config() {
    local conf_file=$1
    local domain=$2
    local certbot_version=$3
    
    cp "$conf_file" "$conf_file.backup"
    
    cat > "$conf_file" << EOF
version = $certbot_version
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
}

# Verify imported certificates
verify_imported_certificates() {
    echo -e "${CYAN}${INFO}${NC} Performing critical certificate validation..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would verify certificates with 'certbot certificates'${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Testing certbot certificate reading"
        if ! certbot certificates >/dev/null 2>&1; then
            echo -e "${RED}${CROSS}${NC} Critical error: Certbot cannot read imported certificates"
            echo
            log_operation "IMPORT: FAILED - certificate validation error"
            rollback
            exit 1
        fi
        
        echo -e "${GRAY}  ${ARROW}${NC} Verifying individual certificate files"
        verify_individual_certificates
    fi
    echo -e "${GREEN}${CHECK}${NC} Certificate verification completed successfully!"
}

# Verify individual certificates
verify_individual_certificates() {
    local validation_failed=0
    
    for live_dir in /etc/letsencrypt/live/*/; do
        [ ! -d "$live_dir" ] && continue
        local domain=$(basename "$live_dir")
        [ "$domain" = "*" ] && continue
        
        if [ -f "$live_dir/fullchain.pem" ]; then
            if ! openssl x509 -in "$live_dir/fullchain.pem" -noout -text >/dev/null 2>&1; then
                echo -e "${RED}${CROSS}${NC} $domain certificate is invalid"
                validation_failed=1
            fi
        else
            echo -e "${RED}${CROSS}${NC} $domain missing fullchain.pem"
            validation_failed=1
        fi
    done
    
    if [ "$validation_failed" -eq 1 ]; then
        echo -e "${RED}${CROSS}${NC} Certificate validation failed"
        echo
        log_operation "IMPORT: FAILED - certificate validation"
        rollback
        exit 1
    fi
}

# Handle renewal test failure
handle_renewal_test_failure() {
    echo -e "${RED}${CROSS}${NC} Certificate renewal test FAILED"
    echo
    echo -e "${YELLOW}Certificate renewal may not work.${NC}"
    echo -e "${YELLOW}Check Cloudflare credentials and DNS settings.${NC}"
    log_operation "IMPORT: Renewal test FAILED"
    
    echo -ne "${YELLOW}Continue despite renewal test failure? (y/N): ${NC}"
    read CONTINUE_ANYWAY
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Import cancelled by user${NC}"
        echo
        rollback
        exit 1
    fi
}

# Test certificate renewal
test_certificate_renewal() {
    echo -e "${CYAN}${INFO}${NC} Testing certificate renewal capability..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would test renewal with 'certbot renew --dry-run'${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Running certbot renew --dry-run"
        if certbot renew --dry-run > /dev/null 2>&1; then
            log_operation "IMPORT: Renewal test PASSED"
        else
            handle_renewal_test_failure
        fi
    fi
    echo -e "${GREEN}${CHECK}${NC} Renewal testing completed successfully!"
}

# Handle renewal test failure
handle_renewal_test_failure() {
    echo -e "${RED}${CROSS}${NC} Certificate renewal test FAILED"
    echo
    echo -e "${YELLOW}Certificate renewal may not work.${NC}"
    echo -e "${YELLOW}Check Cloudflare credentials and DNS settings.${NC}"
    log_operation "IMPORT: Renewal test FAILED"
    
    echo -ne "${YELLOW}Continue despite renewal test failure? (y/N): ${NC}"
    read CONTINUE_ANYWAY
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Import cancelled by user${NC}"
        echo
        rollback
        exit 1
    fi
}

# Cleanup temporary files
cleanup_temporary_files() {
    echo -e "${CYAN}${INFO}${NC} Cleaning up temporary files..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN] Would remove backup archive${NC}"
    else
        echo -e "${GRAY}  ${ARROW}${NC} Removing backup archive"
        rm -f "$BACKUP_FILE"
        log_operation "IMPORT: Completed successfully, cleaned up $BACKUP_FILE"
    fi
    echo -e "${GREEN}${CHECK}${NC} Cleanup completed successfully!"
}

# Display import completion info
display_import_completion_info() {
    echo
    echo -e "${PURPLE}====================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GREEN}${CHECK}${NC} IMPORT DRY-RUN COMPLETED!"
        echo -e "${CYAN}                No changes were made${NC}"
    else
        echo -e "${GREEN}${CHECK}${NC} IMPORT COMPLETED!"
    fi
    echo -e "${PURPLE}====================${NC}"
    echo
    
    if [ "$DRY_RUN" != true ]; then
        echo -e "${CYAN}Imported Certificates:${NC}"
        list_imported_certificates
        echo
        echo -e "${CYAN}Useful Commands:${NC}"
        echo -e "${WHITE}• Check certificates: certbot certificates${NC}"
        echo -e "${WHITE}• Test renewal: certbot renew --dry-run${NC}"
        echo -e "${WHITE}• Force renewal: certbot renew --force-renewal${NC}"
    fi
}

# List imported certificates
list_imported_certificates() {
    ls -1 /etc/letsencrypt/live 2>/dev/null | grep -v README | while read domain; do
        if [ -n "$domain" ]; then
            echo -e "${WHITE}• $domain${NC}"
        fi
    done
}

#=============================
# MAIN EXPORT FUNCTION
#=============================

# Export certificates
export_certificates() {
    set -e
    
    echo
    echo -e "${PURPLE}===================${NC}"
    echo -e "${WHITE}CERTIFICATE EXPORT${NC}"
    echo -e "${PURPLE}===================${NC}"
    
    echo
    echo -e "${GREEN}Certificate Validation${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo

    validate_existing_certificates

    echo
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Certificate validation completed successfully!"
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Backup Creation${NC}"
    echo -e "${GREEN}===============${NC}"
    echo

    create_backup_archive

    echo
    echo -e "${GREEN}──────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Backup creation completed successfully!"
    echo -e "${GREEN}──────────────────────────────────────────${NC}"

    display_export_completion_info
}

#=============================
# MAIN IMPORT FUNCTION
#=============================

# Import certificates
import_certificates() {
    if [ "$DRY_RUN" != true ]; then
        set -e
    fi
    
    echo
    echo -e "${PURPLE}===================${NC}"
    echo -e "${WHITE}CERTIFICATE IMPORT${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}                  (DRY-RUN MODE)${NC}"
    fi
    echo -e "${PURPLE}===================${NC}"

    echo
    echo -e "${GREEN}Archive Verification${NC}"
    echo -e "${GREEN}====================${NC}"
    echo

    verify_archive_integrity

    echo
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Archive verification completed successfully!"
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Certbot Installation${NC}"
    echo -e "${GREEN}====================${NC}"
    echo

    if ! command -v certbot &> /dev/null; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "${YELLOW}[DRY-RUN] Would install certbot and DNS plugins${NC}"
        else
            install_certbot_package
        fi
    else
        echo -e "${GREEN}${CHECK}${NC} Certbot already installed"
    fi

    echo
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Certbot installation completed successfully!"
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Credential Validation${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo

    validate_import_credentials

    echo
    echo -e "${GREEN}────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Credential validation completed successfully!"
    echo -e "${GREEN}────────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Data Backup${NC}"
    echo -e "${GREEN}===========${NC}"
    echo

    backup_existing_data

    echo
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Data backup completed successfully!"
    echo -e "${GREEN}──────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Certificate Extraction${NC}"
    echo -e "${GREEN}======================${NC}"
    echo

    extract_certificate_archive

    echo
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Certificate extraction completed successfully!"
    echo -e "${GREEN}─────────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Structure Fixing${NC}"
    echo -e "${GREEN}================${NC}"
    echo

    fix_certificate_structure

    echo
    echo -e "${GREEN}───────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Structure fixing completed successfully!"
    echo -e "${GREEN}───────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Configuration Update${NC}"
    echo -e "${GREEN}====================${NC}"
    echo

    update_renewal_configurations

    echo
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Configuration update completed successfully!"
    echo -e "${GREEN}───────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Certificate Verification${NC}"
    echo -e "${GREEN}========================${NC}"
    echo

    verify_imported_certificates

    echo
    echo -e "${GREEN}───────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Certificate verification completed successfully!"
    echo -e "${GREEN}───────────────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Renewal Testing${NC}"
    echo -e "${GREEN}===============${NC}"
    echo

    test_certificate_renewal

    echo
    echo -e "${GREEN}──────────────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Renewal testing completed successfully!"
    echo -e "${GREEN}──────────────────────────────────────────${NC}"

    echo
    echo -e "${GREEN}Cleanup${NC}"
    echo -e "${GREEN}=======${NC}"
    echo

    cleanup_temporary_files

    echo
    echo -e "${GREEN}──────────────────────────────────${NC}"
    echo -e "${GREEN}${CHECK}${NC} Cleanup completed successfully!"
    echo -e "${GREEN}──────────────────────────────────${NC}"

    display_import_completion_info
}

#==================
# MAIN ENTRY POINT
#==================

# Parse command line arguments
parse_arguments() {
    case "$1" in
        "export"|"--export"|"-e")
            ACTION="export"
            ;;
        "import"|"--import"|"-i")
            ACTION="import"
            setup_cloudflare_credentials
            ;;
        "--dry-run"|"-d")
            ACTION="import"
            DRY_RUN=true
            echo -e "${YELLOW}Running in DRY-RUN mode (no changes will be made)${NC}"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Main function
main() {
    # Setup error handling
    trap 'echo -e "${RED}Error occurred, attempting rollback...${NC}"; rollback; exit 1' ERR
    
    # Run critical checks
    check_root_privileges
    
    # Parse command line arguments
    if ! parse_arguments "$1"; then
        # Interactive menu
        while true; do
            show_main_menu
            echo -ne "${CYAN}Enter your choice (1-3): ${NC}"
            read CHOICE
            handle_user_choice "$CHOICE"
            break
        done
    fi
    
    # Execute the requested action
    case "$ACTION" in
        "export")
            export_certificates
            ;;
        "import")
            import_certificates
            ;;
    esac
    
    echo
}

# Execute main function with all arguments
main "$@"
