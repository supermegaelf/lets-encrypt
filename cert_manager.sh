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
echo -e "${WHITE}Let's Encrypt Certificate Manager${NC}"
echo -e "${PURPLE}==================================${NC}"

# Logging function
log_operation() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/cert_manager.log
}

# Rollback function
rollback() {
    if [ -d "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" ]; then
        echo -e "${YELLOW}Rolling back changes...${NC}"
        rm -rf /etc/letsencrypt
        mv "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP" /etc/letsencrypt
        echo -e "${GREEN}✓ Rollback completed${NC}"
        log_operation "ROLLBACK: Restored from backup.$BACKUP_TIMESTAMP"
    fi
}

# Trap for error handling
trap 'echo -e "${RED}Error occurred, attempting rollback...${NC}"; rollback; exit 1' ERR

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
   echo -e "${CYAN}Please select an action:${NC}"
   echo
   echo -e "${GREEN}1.${NC} Export certificates"
   echo -e "${GREEN}2.${NC} Import certificates"
   echo -e "${GREEN}3.${NC} Import certificates (dry-run)"
   echo -e "${YELLOW}4.${NC} Exit"
   echo
   
   while true; do
       read -p "Enter your choice (1-4): " CHOICE
       case $CHOICE in
           1)
               ACTION="export"
               break
               ;;
           2)
               ACTION="import"
               break
               ;;
           3)
               ACTION="import"
               DRY_RUN=true
               echo -e "${YELLOW}Running in DRY-RUN mode${NC}"
               break
               ;;
           4)
               echo -e "${CYAN}Goodbye!${NC}"
               exit 0
               ;;
           *)
               echo -e "${RED}Invalid choice. Please enter 1, 2, 3, or 4.${NC}"
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

   echo -e "${GREEN}==================================${NC}"
   echo -e "${NC}1. Checking existing certificates${NC}"
   echo -e "${GREEN}==================================${NC}"
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

   echo "Found certificates for domains:"
   ls -1 /etc/letsencrypt/live | grep -v README | while read domain; do
       if [ -n "$domain" ]; then
           # Validate certificate
           if openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -text >/dev/null 2>&1; then
               echo -e "  ${GREEN}✓${NC} $domain (valid)"
           else
               echo -e "  ${RED}✗${NC} $domain (invalid certificate)"
           fi
       fi
   done

   echo
   echo -e "${GREEN}----------------------------------${NC}"
   echo -e "${NC}✓ Certificate checking completed!${NC}"
   echo -e "${GREEN}----------------------------------${NC}"
   echo

   echo -e "${GREEN}===================${NC}"
   echo -e "${NC}2. Creating backup${NC}"
   echo -e "${GREEN}===================${NC}"
   echo

   # Remove old backup if exists
   if [ -f "$BACKUP_FILE" ]; then
       echo "Removing old backup..."
       rm -f "$BACKUP_FILE"
   fi

   # Create backup archive with verification
   echo "Creating certificate backup..."
   if tar --preserve-permissions -czf "$BACKUP_FILE" -C /etc letsencrypt/; then
       echo -e "${GREEN}✓ Backup created successfully${NC}"
       
       # Verify archive integrity
       if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
           echo -e "${GREEN}✓ Archive integrity verified${NC}"
       else
           echo -e "${RED}✗ Archive verification failed${NC}"
           rm -f "$BACKUP_FILE"
           exit 1
       fi
       
       # Show archive size
       ARCHIVE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
       echo -e "${BLUE}Archive size: $ARCHIVE_SIZE${NC}"
   else
       echo -e "${RED}Failed to create backup archive!${NC}"
       exit 1
   fi

   log_operation "EXPORT: Created backup $BACKUP_FILE ($ARCHIVE_SIZE)"

   echo
   echo -e "${GREEN}-----------------------------${NC}"
   echo -e "${NC}✓ Backup creation completed!${NC}"
   echo -e "${GREEN}-----------------------------${NC}"
   echo

   echo -e "${GREEN}=============================================${NC}"
   echo -e "${NC}✓ Certificate export completed successfully!${NC}"
   echo -e "${GREEN}=============================================${NC}"
   echo
   echo -e "${CYAN}Export Information:${NC}"
   echo -e "Backup file: ${WHITE}$BACKUP_FILE${NC}"
   echo -e "Archive size: ${WHITE}$ARCHIVE_SIZE${NC}"
   echo
   echo -e "${CYAN}Next Steps:${NC}"
   echo -e "1. Transfer ${WHITE}$BACKUP_FILE${NC} to your new server"
   echo -e "2. Run: ${WHITE}./cert_manager.sh import${NC} on the new server"
   echo -e "3. Or test first: ${WHITE}./cert_manager.sh --dry-run${NC}"
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

   echo -e "${GREEN}===========================${NC}"
   echo -e "${NC}1. Checking backup archive${NC}"
   echo -e "${GREEN}===========================${NC}"
   echo

   # Check if backup archive exists
   if [ ! -f "$BACKUP_FILE" ]; then
       echo -e "${RED}Backup archive not found: $BACKUP_FILE${NC}"
       echo -e "${RED}Please transfer the backup file to /root/ first${NC}"
       exit 1
   fi

   echo -e "${BLUE}Found backup archive: $BACKUP_FILE${NC}"
   ARCHIVE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
   echo -e "${BLUE}Archive size: $ARCHIVE_SIZE${NC}"

   # Verify archive integrity
   echo "Verifying archive integrity..."
   if ! tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
       echo -e "${RED}Archive is corrupted or invalid!${NC}"
       exit 1
   fi

   # Check if archive contains Let's Encrypt structure
   if ! tar -tzf "$BACKUP_FILE" | grep -q "letsencrypt/live"; then
       echo -e "${RED}Archive doesn't contain Let's Encrypt live directory!${NC}"
       exit 1
   fi

   if ! tar -tzf "$BACKUP_FILE" | grep -q "letsencrypt/archive"; then
       echo -e "${YELLOW}Warning: Archive doesn't contain archive directory${NC}"
   fi

   echo -e "${GREEN}✓ Archive verification passed${NC}"

   echo
   echo -e "${GREEN}-------------------------------------${NC}"
   echo -e "${NC}✓ Backup archive checking completed!${NC}"
   echo -e "${GREEN}-------------------------------------${NC}"
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
           apt-get update -y
           apt-get install -y certbot python3-certbot-dns-cloudflare
           echo -e "${GREEN}✓ Certbot installed${NC}"
       fi
   else
       echo -e "${GREEN}✓ Certbot already installed${NC}"
       CERTBOT_VERSION=$(certbot --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
       echo -e "${BLUE}Certbot version: $CERTBOT_VERSION${NC}"
   fi

   echo
   echo -e "${GREEN}----------------------------------${NC}"
   echo -e "${NC}✓ Certbot installation completed!${NC}"
   echo -e "${GREEN}----------------------------------${NC}"
   echo

   echo -e "${GREEN}============================${NC}"
   echo -e "${NC}3. Backing up existing data${NC}"
   echo -e "${GREEN}============================${NC}"
   echo

   # Backup existing certificates if they exist
   if [ -d "/etc/letsencrypt" ]; then
       if [ "$DRY_RUN" = true ]; then
           echo -e "${YELLOW}[DRY-RUN] Would backup existing certificates to /etc/letsencrypt.backup.$BACKUP_TIMESTAMP${NC}"
       else
           echo "Creating backup of existing certificates..."
           cp -r /etc/letsencrypt "/etc/letsencrypt.backup.$BACKUP_TIMESTAMP"
           echo -e "${GREEN}✓ Existing data backed up to /etc/letsencrypt.backup.$BACKUP_TIMESTAMP${NC}"
           log_operation "IMPORT: Backed up existing certs to backup.$BACKUP_TIMESTAMP"
       fi
   else
       echo -e "${GREEN}✓ No existing certificates to backup${NC}"
   fi

   echo
   echo -e "${GREEN}----------------------------------${NC}"
   echo -e "${NC}✓ Existing data backup completed!${NC}"
   echo -e "${GREEN}----------------------------------${NC}"
   echo

   echo -e "${GREEN}===========================${NC}"
   echo -e "${NC}4. Extracting certificates${NC}"
   echo -e "${GREEN}===========================${NC}"
   echo

   # Extract backup archive
   echo "Extracting certificate archive..."
   if [ "$DRY_RUN" = true ]; then
       echo -e "${YELLOW}[DRY-RUN] Would extract certificates to /etc/${NC}"
       # Show what would be extracted
       echo "Archive contents:"
       tar -tzf "$BACKUP_FILE" | head -20
       if [ $(tar -tzf "$BACKUP_FILE" | wc -l) -gt 20 ]; then
           echo "... and $(( $(tar -tzf "$BACKUP_FILE" | wc -l) - 20 )) more files"
       fi
   else
       # Remove existing letsencrypt directory
       rm -rf /etc/letsencrypt
       
       if tar -xzf "$BACKUP_FILE" -C /etc/; then
           echo -e "${GREEN}✓ Certificates extracted successfully${NC}"
       else
           echo -e "${RED}Failed to extract certificate archive!${NC}"
           rollback
           exit 1
       fi

       # Set proper permissions
       echo "Setting file permissions..."
       chown -R root:root /etc/letsencrypt
       chmod -R 600 /etc/letsencrypt
       chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
   fi

   echo
   echo -e "${GREEN}------------------------------------${NC}"
   echo -e "${NC}✓ Certificate extraction completed!${NC}"
   echo -e "${GREEN}------------------------------------${NC}"
   echo

   echo -e "${GREEN}================================${NC}"
   echo -e "${NC}5. Fixing certificate structure${NC}"
   echo -e "${GREEN}================================${NC}"
   echo

   # Fix certificate structure
   echo "Checking and fixing certificate structure..."

   if [ "$DRY_RUN" = true ]; then
       echo -e "${YELLOW}[DRY-RUN] Would check and fix certificate symlink structure${NC}"
   else
       for live_dir in /etc/letsencrypt/live/*/; do
           [ ! -d "$live_dir" ] && continue

           domain=$(basename "$live_dir")
           [ "$domain" = "*" ] && continue

           echo -e "Processing domain: ${GREEN}$domain${NC}"

           archive_dir="/etc/letsencrypt/archive/$domain"
           mkdir -p "$archive_dir"

           # Check if files in live are not symlinks
           if [ -f "$live_dir/fullchain.pem" ] && [ ! -L "$live_dir/fullchain.pem" ]; then
               echo "  Fixing symlink structure..."

               # Move files to archive with error handling
               for file in "$live_dir"/*.pem; do
                   if [ -f "$file" ]; then
                       mv "$file" "$archive_dir/" 2>/dev/null || echo "  Warning: Could not move $(basename "$file")"
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
                   echo "  Extracting cert.pem from fullchain.pem..."
                   if ! openssl x509 -in fullchain1.pem -out cert1.pem 2>/dev/null; then
                       echo "  Warning: Could not extract cert from fullchain"
                   fi
               fi

               if [ ! -f chain1.pem ] && [ -f fullchain1.pem ]; then
                   echo "  Extracting chain.pem from fullchain.pem..."
                   if ! sed '1,/-----END CERTIFICATE-----/d' fullchain1.pem > chain1.pem; then
                       echo "  Warning: Could not extract chain from fullchain"
                   fi
               fi

               # Create symlinks with error handling
               cd "$live_dir"
               for cert_type in fullchain privkey cert chain; do
                   if [ -f "$archive_dir/${cert_type}1.pem" ]; then
                       ln -sf "../../archive/$domain/${cert_type}1.pem" "${cert_type}.pem"
                   else
                       echo "  Warning: Missing ${cert_type}1.pem in archive"
                   fi
               done

               echo -e "  ${GREEN}✓ Structure fixed${NC}"
           else
               echo -e "  ${GREEN}✓ Structure already correct${NC}"
           fi
       done
   fi

   echo
   echo -e "${GREEN}------------------------------------------${NC}"
   echo -e "${NC}✓ Certificate structure fixing completed!${NC}"
   echo -e "${GREEN}------------------------------------------${NC}"
   echo

   echo -e "${GREEN}============================${NC}"
   echo -e "${NC}6. Updating renewal configs${NC}"
   echo -e "${GREEN}============================${NC}"
   echo

   # Update renewal configurations
   echo "Updating renewal configurations for new server..."

   # Get certbot version safely
   CERTBOT_VERSION=$(certbot --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
   CERTBOT_VERSION=${CERTBOT_VERSION:-"2.11.0"}

   # Check for Cloudflare credentials
   CREDENTIALS_PATH="/root/.secrets/certbot/cloudflare.ini"
   if [ ! -f "$CREDENTIALS_PATH" ]; then
       echo -e "${YELLOW}Warning: Cloudflare credentials not found at $CREDENTIALS_PATH${NC}"
       echo -e "${YELLOW}Renewal may fail without proper credentials${NC}"
   fi

   if [ "$DRY_RUN" = true ]; then
       echo -e "${YELLOW}[DRY-RUN] Would update renewal configurations${NC}"
       echo "Would use certbot version: $CERTBOT_VERSION"
       echo "Credentials path: $CREDENTIALS_PATH"
   else
       for conf_file in /etc/letsencrypt/renewal/*.conf; do
           [ ! -f "$conf_file" ] && continue

           domain=$(basename "$conf_file" .conf)
           echo "  Updating configuration for $domain"

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

       echo -e "${GREEN}✓ Renewal configurations updated${NC}"
   fi

   echo
   echo -e "${GREEN}-----------------------------------${NC}"
   echo -e "${NC}✓ Renewal config update completed!${NC}"
   echo -e "${GREEN}-----------------------------------${NC}"
   echo

   echo -e "${GREEN}==========================${NC}"
   echo -e "${NC}7. Verifying certificates${NC}"
   echo -e "${GREEN}==========================${NC}"
   echo

   # Verify imported certificates
   echo "Verifying imported certificates..."
   if [ "$DRY_RUN" = true ]; then
       echo -e "${YELLOW}[DRY-RUN] Would verify certificates with 'certbot certificates'${NC}"
   else
       if certbot certificates 2>/dev/null; then
           echo -e "${GREEN}✓ Certificate verification completed${NC}"
       else
           echo -e "${YELLOW}Warning: Certificate verification had issues${NC}"
           echo -e "${YELLOW}You may need to check the certificates manually${NC}"
       fi
   fi

   echo
   echo -e "${GREEN}--------------------------------------${NC}"
   echo -e "${NC}✓ Certificate verification completed!${NC}"
   echo -e "${GREEN}--------------------------------------${NC}"
   echo

   echo -e "${GREEN}===============${NC}"
   echo -e "${NC}8. Cleaning up${NC}"
   echo -e "${GREEN}===============${NC}"
   echo

   # Clean up backup file
   if [ "$DRY_RUN" = true ]; then
       echo -e "${YELLOW}[DRY-RUN] Would remove backup archive${NC}"
   else
       echo "Removing backup archive..."
       rm -f "$BACKUP_FILE"
       echo -e "${GREEN}✓ Backup archive removed${NC}"
       log_operation "IMPORT: Completed successfully, cleaned up $BACKUP_FILE"
   fi

   echo
   echo -e "${GREEN}---------------------${NC}"
   echo -e "${NC}✓ Cleanup completed!${NC}"
   echo -e "${GREEN}---------------------${NC}"
   echo

   echo -e "${GREEN}=============================================${NC}"
   if [ "$DRY_RUN" = true ]; then
       echo -e "${NC}✓ Certificate import DRY-RUN completed successfully!${NC}"
       echo -e "${CYAN}No changes were made to the system.${NC}"
   else
       echo -e "${NC}✓ Certificate import completed successfully!${NC}"
   fi
   echo -e "${GREEN}=============================================${NC}"
   echo
   
   if [ "$DRY_RUN" != true ]; then
       echo -e "${CYAN}Imported Certificates:${NC}"
       ls -1 /etc/letsencrypt/live 2>/dev/null | grep -v README | while read domain; do
           if [ -n "$domain" ]; then
               echo -e "  ${GREEN}✓${NC} $domain"
           fi
       done
   fi
   
   echo
   echo -e "${CYAN}Recommendations:${NC}"
   echo -e "Test renewal: ${WHITE}sudo certbot renew --dry-run${NC}"
   echo -e "Check expiration: ${WHITE}sudo certbot certificates${NC}"
   if [ -f "$CREDENTIALS_PATH" ]; then
       echo -e "Credentials found: ${GREEN}✓${NC} $CREDENTIALS_PATH"
   else
       echo -e "Setup credentials: ${YELLOW}Configure Cloudflare API credentials${NC}"
   fi
   echo

   exit 0
fi
