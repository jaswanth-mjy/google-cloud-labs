#!/bin/bash

# Minecraft Server Lab Automation Script
# This script automates the setup of a Minecraft server on Google Cloud Platform

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Minecraft Server Lab Automation${NC}"
echo -e "${GREEN}========================================${NC}"

# Set default region and zone
REGION="europe-west1"
ZONE="europe-west1-b"

# Task 1: Create the VM with advanced configuration
echo -e "\n${YELLOW}Task 1: Creating Minecraft Server VM...${NC}"

# Check if VM already exists
if gcloud compute instances describe mc-server --zone=$ZONE &>/dev/null; then
    echo -e "${GREEN}✓ VM 'mc-server' already exists. Skipping creation.${NC}"
else
    # Reserve static IP address first
    if ! gcloud compute addresses describe mc-server-ip --region=$REGION &>/dev/null; then
        echo "Creating static external IP address..."
        gcloud compute addresses create mc-server-ip \
            --region=$REGION \
            --quiet
        echo -e "${GREEN}✓ Static IP 'mc-server-ip' created${NC}"
    else
        echo -e "${GREEN}✓ Static IP 'mc-server-ip' already exists${NC}"
    fi
    
    # Create blank persistent SSD disk
    if ! gcloud compute disks describe minecraft-disk --zone=$ZONE &>/dev/null; then
        echo "Creating SSD persistent disk for Minecraft data..."
        gcloud compute disks create minecraft-disk \
            --size=50GB \
            --type=pd-ssd \
            --zone=$ZONE \
            --quiet
        echo -e "${GREEN}✓ Disk 'minecraft-disk' created${NC}"
    else
        echo -e "${GREEN}✓ Disk 'minecraft-disk' already exists${NC}"
    fi
    
    # Get the static IP address
    STATIC_IP=$(gcloud compute addresses describe mc-server-ip --region=$REGION --format="get(address)")
    
    # Create the VM instance
    echo "Creating Minecraft server VM..."
    gcloud compute instances create mc-server \
        --zone=$ZONE \
        --machine-type=e2-medium \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard \
        --disk=name=minecraft-disk,mode=rw,boot=no \
        --tags=minecraft-server \
        --address=$STATIC_IP \
        --scopes=storage-rw \
        --quiet
    
    echo -e "${GREEN}✓ VM 'mc-server' created successfully${NC}"
    
    # Wait for VM to be ready
    echo "Waiting for VM to be ready..."
    sleep 30
fi

# Task 2: Prepare the data disk
echo -e "\n${YELLOW}Task 2: Preparing the data disk...${NC}"

# Execute disk preparation commands on the VM
gcloud compute ssh mc-server --zone=$ZONE --command="
    # Check if already mounted
    if mount | grep -q '/home/minecraft'; then
        echo 'Disk already mounted'
    else
        # Create mount directory
        sudo mkdir -p /home/minecraft
        
        # Check if disk is already formatted
        if sudo file -s /dev/disk/by-id/google-minecraft-disk | grep -q 'ext4'; then
            echo 'Disk already formatted'
        else
            # Format the disk
            sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-minecraft-disk
        fi
        
        # Mount the disk
        sudo mount -o discard,defaults /dev/disk/by-id/google-minecraft-disk /home/minecraft
        echo 'Disk mounted successfully'
    fi
" --quiet

echo -e "${GREEN}✓ Data disk prepared and mounted${NC}"

# Task 3: Install and run the Minecraft application
echo -e "\n${YELLOW}Task 3: Installing and running Minecraft server...${NC}"

gcloud compute ssh mc-server --zone=$ZONE --command="
    # Update repositories
    sudo apt-get update -y
    
    # Install Java Runtime Environment (headless)
    if ! command -v java &>/dev/null; then
        sudo apt-get install -y default-jre-headless
    fi
    
    # Navigate to Minecraft directory
    cd /home/minecraft
    
    # Install wget if needed
    if ! command -v wget &>/dev/null; then
        sudo apt-get install -y wget
    fi
    
    # Download Minecraft server if not already present
    if [ ! -f server.jar ]; then
        sudo wget https://launcher.mojang.com/v1/objects/d0d0fe2b1dc6ab4c65554cb734270872b72dadd6/server.jar
    fi
    
    # Initialize server if not already done
    if [ ! -f eula.txt ]; then
        sudo java -Xmx1024M -Xms1024M -jar server.jar nogui || true
    fi
    
    # Accept EULA
    if [ -f eula.txt ]; then
        sudo sed -i 's/eula=false/eula=true/' eula.txt
    fi
    
    # Install screen if not present
    if ! command -v screen &>/dev/null; then
        sudo apt-get install -y screen
    fi
    
    # Check if Minecraft server is already running
    if sudo screen -list | grep -q mcs; then
        echo 'Minecraft server already running'
    else
        # Start Minecraft server in screen session
        sudo screen -dmS mcs java -Xmx1024M -Xms1024M -jar server.jar nogui
        echo 'Minecraft server started in screen session'
    fi
" --quiet

echo -e "${GREEN}✓ Minecraft server installed and running${NC}"

# Task 4: Allow client traffic (create firewall rule)
echo -e "\n${YELLOW}Task 4: Configuring firewall for client traffic...${NC}"

if gcloud compute firewall-rules describe minecraft-rule &>/dev/null; then
    echo -e "${GREEN}✓ Firewall rule 'minecraft-rule' already exists${NC}"
else
    gcloud compute firewall-rules create minecraft-rule \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:25565 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=minecraft-server \
        --quiet
    
    echo -e "${GREEN}✓ Firewall rule created to allow Minecraft client traffic on TCP port 25565${NC}"
fi

# Task 5: Schedule regular backups
echo -e "\n${YELLOW}Task 5: Setting up regular backups...${NC}"

# Get project ID
PROJECT_ID=$(gcloud config get-value project)

gcloud compute ssh mc-server --zone=$ZONE --command="
    # Set bucket name environment variable
    export YOUR_BUCKET_NAME=${PROJECT_ID}
    
    # Create Cloud Storage bucket if it doesn't exist
    if ! gcloud storage buckets describe gs://\${YOUR_BUCKET_NAME}-minecraft-backup &>/dev/null; then
        gcloud storage buckets create gs://\${YOUR_BUCKET_NAME}-minecraft-backup
        echo 'Cloud Storage bucket created'
    else
        echo 'Bucket already exists'
    fi
    
    # Create backup script
    sudo bash -c 'cat > /home/minecraft/backup.sh' << 'EOF'
#!/bin/bash
screen -r mcs -X stuff '/save-all\n/save-off\n'
/usr/bin/gcloud storage cp -R \${BASH_SOURCE%/*}/world gs://\${YOUR_BUCKET_NAME}-minecraft-backup/\$(date \"+%Y%m%d-%H%M%S\")-world
screen -r mcs -X stuff '/save-on\n'
EOF
    
    # Make script executable
    sudo chmod 755 /home/minecraft/backup.sh
    
    # Add environment variable to profile
    echo \"export YOUR_BUCKET_NAME=${PROJECT_ID}\" | sudo tee -a /root/.profile
    
    # Test the backup script
    export YOUR_BUCKET_NAME=${PROJECT_ID}
    cd /home/minecraft
    sudo -E ./backup.sh
    
    # Schedule cron job (every 4 hours)
    # Check if cron job already exists
    if ! sudo crontab -l 2>/dev/null | grep -q 'backup.sh'; then
        (sudo crontab -l 2>/dev/null; echo '0 */4 * * * /home/minecraft/backup.sh') | sudo crontab -
        echo 'Cron job scheduled for backups every 4 hours'
    else
        echo 'Cron job already exists'
    fi
" --quiet

echo -e "${GREEN}✓ Backup system configured with 4-hour intervals${NC}"

# Task 6: Configure server maintenance scripts
echo -e "\n${YELLOW}Task 6: Configuring server maintenance scripts...${NC}"

# Add startup and shutdown scripts to VM metadata
gcloud compute instances add-metadata mc-server \
    --zone=$ZONE \
    --metadata=startup-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/startup.sh,shutdown-script-url=https://storage.googleapis.com/cloud-training/archinfra/mcserver/shutdown.sh \
    --quiet

echo -e "${GREEN}✓ Startup and shutdown scripts configured${NC}"

# Display summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Lab Completion Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Task 1: VM created with static IP and SSD disk${NC}"
echo -e "${GREEN}✓ Task 2: Data disk formatted and mounted${NC}"
echo -e "${GREEN}✓ Task 3: Minecraft server installed and running${NC}"
echo -e "${GREEN}✓ Task 4: Firewall rule configured for TCP:25565${NC}"
echo -e "${GREEN}✓ Task 5: Backup system configured (every 4 hours)${NC}"
echo -e "${GREEN}✓ Task 6: Maintenance scripts configured${NC}"

# Get external IP
EXTERNAL_IP=$(gcloud compute addresses describe mc-server-ip --region=$REGION --format="get(address)")
echo -e "\n${YELLOW}Minecraft Server External IP: ${GREEN}${EXTERNAL_IP}${NC}"
echo -e "${YELLOW}You can test the server at: https://mcsrvstat.us/server/${EXTERNAL_IP}${NC}"

echo -e "\n${GREEN}All tasks completed successfully!${NC}"
