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
echo

# Check if script is run with parameters
if [ "$1" = "export" ] || [ "$1" = "--export" ] || [ "$1" = "-e" ]; then
   ACTION="export"
elif [ "$1" = "import" ] || [ "$1" = "--import" ] || [ "$1" = "-i" ]; then
   ACTION="import"
else
   # Interactive menu
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
       echo -e "  ${GREEN}✓${NC} $domain"
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

   # Create backup archive
   echo "Creating certificate backup..."
   if tar --preserve-permissions -czf "$BACKUP_FILE" -C /etc letsencrypt/; then
       echo -e "${GREEN}✓ Backup created successfully${NC}"
       
       # Show archive size
       ARCHIVE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
       echo -e "${BLUE}Archive size: $ARCHIVE_SIZE${NC}"
   else
       echo -e "${RED}Failed to create backup archive!${NC}"
       exit 1
   fi

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
   echo

   exit 0
fi

# Import function
if [ "$ACTION" = "import" ]; then
   echo
   echo -e "${PURPLE}===================${NC}"
   echo -e "${WHITE}Certificate Import${NC}"
   echo -e "${PURPLE}===================${NC}"
   echo

   set -e

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
       echo "Installing certbot and DNS plugins..."
       apt-get update -y
       apt-get install -y certbot python3-certbot-dns-cloudflare
       echo -e "${GREEN}✓ Certbot installed${NC}"
   else
       echo -e "${GREEN}✓ Certbot already installed${NC}"
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
       BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
       echo "Creating backup of existing certificates..."
       mv /etc/letsencrypt /etc/letsencrypt.backup.$BACKUP_TIMESTAMP
       echo -e "${GREEN}✓ Existing data backed up to /etc/letsencrypt.backup.$BACKUP_TIMESTAMP${NC}"
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
   if tar -xzf "$BACKUP_FILE" -C /etc/; then
       echo -e "${GREEN}✓ Certificates extracted successfully${NC}"
   else
       echo -e "${RED}Failed to extract certificate archive!${NC}"
       exit 1
   fi

   # Set proper permissions
   echo "Setting file permissions..."
   chown -R root:root /etc/letsencrypt
   chmod -R 600 /etc/letsencrypt
   chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive

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

           # Move files to archive
           mv "$live_dir"/*.pem "$archive_dir/" 2>/dev/null

           # Rename with version number
           cd "$archive_dir"
           [ -f fullchain.pem ] && mv fullchain.pem fullchain1.pem
           [ -f privkey.pem ] && mv privkey.pem privkey1.pem
           [ -f cert.pem ] && mv cert.pem cert1.pem
           [ -f chain.pem ] && mv chain.pem chain1.pem

           # Create missing files if needed
           if [ ! -f cert1.pem ] && [ -f fullchain1.pem ]; then
               echo "  Extracting cert.pem from fullchain.pem..."
               openssl x509 -in fullchain1.pem -out cert1.pem
           fi

           if [ ! -f chain1.pem ] && [ -f fullchain1.pem ]; then
               echo "  Extracting chain.pem from fullchain.pem..."
               sed '1,/-----END CERTIFICATE-----/d' fullchain1.pem > chain1.pem
           fi

           # Create symlinks
           ln -sf "../../archive/$domain/fullchain1.pem" "$live_dir/fullchain.pem"
           ln -sf "../../archive/$domain/privkey1.pem" "$live_dir/privkey.pem"
           ln -sf "../../archive/$domain/cert1.pem" "$live_dir/cert.pem"
           ln -sf "../../archive/$domain/chain1.pem" "$live_dir/chain.pem"

           echo -e "  ${GREEN}✓ Structure fixed${NC}"
       else
           echo -e "  ${GREEN}✓ Structure already correct${NC}"
       fi
   done

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

   for conf_file in /etc/letsencrypt/renewal/*.conf; do
       [ ! -f "$conf_file" ] && continue

       domain=$(basename "$conf_file" .conf)
       echo "  Updating configuration for $domain"

       cat > "$conf_file" << EOF
version = 2.11.0
archive_dir = /etc/letsencrypt/archive/$domain
cert = /etc/letsencrypt/live/$domain/cert.pem
privkey = /etc/letsencrypt/live/$domain/privkey.pem
chain = /etc/letsencrypt/live/$domain/chain.pem
fullchain = /etc/letsencrypt/live/$domain/fullchain.pem

[renewalparams]
authenticator = dns-cloudflare
dns_cloudflare_credentials = /root/.secrets/certbot/cloudflare.ini
dns_cloudflare_propagation_seconds = 10
server = https://acme-v02.api.letsencrypt.org/directory
key_type = ecdsa
elliptic_curve = secp384r1
EOF
   done

   echo -e "${GREEN}✓ Renewal configurations updated${NC}"

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
   certbot certificates

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
   echo "Removing backup archive..."
   rm -f "$BACKUP_FILE"
   echo -e "${GREEN}✓ Backup archive removed${NC}"

   echo
   echo -e "${GREEN}---------------------${NC}"
   echo -e "${NC}✓ Cleanup completed!${NC}"
   echo -e "${GREEN}---------------------${NC}"
   echo

   echo -e "${GREEN}=============================================${NC}"
   echo -e "${NC}✓ Certificate import completed successfully!${NC}"
   echo -e "${GREEN}=============================================${NC}"
   echo
   echo -e "${CYAN}Imported Certificates:${NC}"
   ls -1 /etc/letsencrypt/live | grep -v README | while read domain; do
       echo -e "  ${GREEN}✓${NC} $domain"
   done
   echo
   echo -e "${CYAN}Recommendations:${NC}"
   echo -e "Test renewal: ${WHITE}sudo certbot renew --dry-run${NC}"
   echo -e "Check expiration: ${WHITE}sudo certbot certificates${NC}"
   echo

   exit 0
fi
