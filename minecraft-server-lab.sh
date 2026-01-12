#!/bin/bash

# Minecraft Server Lab Automation Script
# This script automates the setup of a Minecraft server on Google Cloud Platform

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution${RESET}"

# Set default zone and derive region from it
export ZONE="europe-west1-b"
export REGION="${ZONE%-*}"

# Task 1: Create the VM with advanced configuration
echo ""
echo "${YELLOW}${BOLD}Task 1: Creating Minecraft Server VM...${RESET}"

# Check if VM already exists
if gcloud compute instances describe mc-server --zone=$ZONE &>/dev/null; then
    echo "${GREEN}✓ VM 'mc-server' already exists. Skipping creation.${RESET}"
else
    # Reserve static IP address
    if ! gcloud compute addresses describe mc-server-ip --region=$REGION &>/dev/null; then
        echo "Creating static external IP address..."
        gcloud compute addresses create mc-server-ip --region=$REGION
        echo "${GREEN}✓ Static IP 'mc-server-ip' created${RESET}"
    else
        echo "${GREEN}✓ Static IP 'mc-server-ip' already exists${RESET}"
    fi
    
    # Get the static IP address
    ADDRESS=$(gcloud compute addresses describe mc-server-ip --region=$REGION --format='value(address)')
    
    # Create the VM instance with all advanced options
    echo "Creating Minecraft server VM..."
    gcloud compute instances create mc-server \
        --project=$DEVSHELL_PROJECT_ID \
        --zone=$ZONE \
        --machine-type=e2-medium \
        --network-interface=address=$ADDRESS,network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
        --metadata=enable-oslogin=true \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --scopes=https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.read_write \
        --tags=minecraft-server \
        --create-disk=auto-delete=yes,boot=yes,device-name=mc-server,image=projects/debian-cloud/global/images/debian-12-bookworm-v20240910,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-standard \
        --create-disk=device-name=minecraft-disk,mode=rw,name=minecraft-disk,size=50,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-ssd \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=goog-ec-src=vm_add-gcloud \
        --reservation-affinity=any
    
    echo "${GREEN}✓ VM 'mc-server' created successfully${RESET}"
    
    # Wait for VM to be ready
    echo "Waiting for VM to be ready..."
    sleep 30
fi

# Task 4: Create firewall rule
echo ""
echo "${YELLOW}${BOLD}Task 4: Creating firewall rule for Minecraft...${RESET}"

if gcloud compute firewall-rules describe minecraft-rule &>/dev/null; then
    echo "${GREEN}✓ Firewall rule 'minecraft-rule' already exists${RESET}"
else
    gcloud compute --project=$DEVSHELL_PROJECT_ID firewall-rules create minecraft-rule \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:25565 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=minecraft-server
    
    echo "${GREEN}✓ Firewall rule created to allow Minecraft client traffic on TCP port 25565${RESET}"
fi

# Add project-id metadata to VM
gcloud compute instances add-metadata mc-server \
    --metadata project-id=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --quiet

# Tasks 2, 3, 5: Prepare disk, install Minecraft, setup backups
echo ""
echo "${YELLOW}${BOLD}Tasks 2, 3, 5: Preparing disk, installing Minecraft, and setting up backups...${RESET}"

# Tasks 2, 3, 5: Prepare disk, install Minecraft, setup backups
echo ""
echo "${YELLOW}${BOLD}Tasks 2, 3, 5: Preparing disk, installing Minecraft, and setting up backups...${RESET}"

cat > prepare_disk.sh <<'EOF_END'

# Task 2: Create directory and prepare disk
sudo mkdir -p /home/minecraft

# Format the disk
sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-minecraft-disk

# Mount the disk
sudo mount -o discard,defaults /dev/disk/by-id/google-minecraft-disk /home/minecraft

# Task 3: Install Java and Minecraft server
sudo apt-get update

sudo apt-get install -y default-jre-headless

cd /home/minecraft

sudo apt-get install wget -y

sudo wget https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar

# Initialize server
sudo java -Xmx1024M -Xms1024M -jar server.jar nogui

# Accept EULA
echo "eula=true" | sudo tee eula.txt

# Install screen
sudo apt-get install -y screen

# Start Minecraft server in screen session (persistent)
sudo screen -dmS mcs java -Xmx1024M -Xms1024M -jar server.jar nogui

echo "Waiting for Minecraft server to initialize..."
sleep 60

# Task 5: Setup backups
PROJECT_ID=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
echo "Project ID: $PROJECT_ID"
export YOUR_BUCKET_NAME=$PROJECT_ID
echo $YOUR_BUCKET_NAME

# Create Cloud Storage bucket
gcloud storage buckets create gs://$YOUR_BUCKET_NAME-minecraft-backup

# Add environment variable to profile
echo "export YOUR_BUCKET_NAME=$YOUR_BUCKET_NAME" | sudo tee -a /root/.profile

# Create backup script inline
sudo bash -c 'cat > /home/minecraft/backup.sh' << 'BACKUP_SCRIPT'
#!/bin/bash
screen -r mcs -X stuff '/save-all\n/save-off\n'
/usr/bin/gcloud storage cp -R ${BASH_SOURCE%/*}/world gs://${YOUR_BUCKET_NAME}-minecraft-backup/$(date "+%Y%m%d-%H%M%S")-world
screen -r mcs -X stuff '/save-on\n'
BACKUP_SCRIPT

# Make backup script executable
sudo chmod 755 /home/minecraft/backup.sh

# Test the backup script
export YOUR_BUCKET_NAME=$PROJECT_ID
cd /home/minecraft
sudo -E ./backup.sh

# Schedule cron job for backups every 4 hours
(sudo crontab -l 2>/dev/null; echo "0 */4 * * * export YOUR_BUCKET_NAME=$PROJECT_ID && /home/minecraft/backup.sh") | sudo crontab -

echo "Backup system configured successfully"

EOF_END

# Copy script to VM
gcloud compute scp prepare_disk.sh mc-server:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet

# Execute script on VM
gcloud compute ssh mc-server --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/prepare_disk.sh"

echo "${GREEN}✓ Data disk prepared, Minecraft server installed and running, backups configured${RESET}"

# Task 6: Configure server maintenance scripts
echo ""
echo "${YELLOW}${BOLD}Task 6: Configuring server maintenance scripts...${RESET}"

gcloud compute instances add-metadata mc-server \
    --metadata project-id=$DEVSHELL_PROJECT_ID,startup-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/startup.sh,shutdown-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/shutdown.sh \
    --zone=$ZONE \
    --quiet

echo "${GREEN}✓ Startup and shutdown scripts configured${RESET}"

# Display completion summary
echo ""
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}${BOLD}Lab Completion Summary${RESET}"
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}✓ Task 1: VM created with static IP and SSD disk${RESET}"
echo "${GREEN}✓ Task 2: Data disk formatted and mounted${RESET}"
echo "${GREEN}✓ Task 3: Minecraft server installed and running${RESET}"
echo "${GREEN}✓ Task 4: Firewall rule configured for TCP:25565${RESET}"
echo "${GREEN}✓ Task 5: Backup system configured (every 4 hours)${RESET}"
echo "${GREEN}✓ Task 6: Maintenance scripts configured${RESET}"

# Get external IP
EXTERNAL_IP=$(gcloud compute addresses describe mc-server-ip --region=$REGION --format="get(address)")
echo ""
echo "${YELLOW}Minecraft Server External IP: ${GREEN}${EXTERNAL_IP}${RESET}"
echo "${YELLOW}You can test the server at: https://mcsrvstat.us/server/${EXTERNAL_IP}${RESET}"

echo ""
echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!!${RESET}"
