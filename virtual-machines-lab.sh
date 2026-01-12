#!/bin/bash

# Creating Virtual Machines Lab - Automated Script
# This script completes all tasks in the Creating Virtual Machines lab

echo "=========================================="
echo "Creating Virtual Machines Lab - Automated"
echo "=========================================="

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[STATUS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ============================================
# Task 1: Create a utility virtual machine
# ============================================
print_status "Task 1: Creating utility virtual machine..."

VM_NAME="utility-vm"
echo "Creating utility VM: $VM_NAME (e2-medium, no external IP)..."

if gcloud compute instances describe $VM_NAME --zone=us-east4-a &>/dev/null; then
    echo "  $VM_NAME already exists, skipping..."
else
    gcloud compute instances create $VM_NAME \
        --zone=us-east4-a \
        --machine-type=e2-medium \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard \
        --no-address
    
    print_status "Utility VM created successfully!"
fi

# ============================================
# Task 2: Create a Windows virtual machine
# ============================================
print_status "Task 2: Creating Windows virtual machine..."

WINDOWS_VM="windows-vm"
echo "Creating Windows VM: $WINDOWS_VM (Windows Server 2016)..."

if gcloud compute instances describe $WINDOWS_VM --zone=us-east4-a &>/dev/null; then
    echo "  $WINDOWS_VM already exists, skipping..."
else
    gcloud compute instances create $WINDOWS_VM \
        --zone=us-east4-a \
        --machine-type=e2-standard-2 \
        --image-family=windows-2016-core \
        --image-project=windows-cloud \
        --boot-disk-size=64GB \
        --boot-disk-type=pd-ssd \
        --tags=http-server,https-server
    
    # Create firewall rules for HTTP and HTTPS if they don't exist
    echo "Creating firewall rules for HTTP and HTTPS..."
    gcloud compute firewall-rules create allow-http \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server 2>/dev/null || echo "  HTTP rule already exists"
    
    gcloud compute firewall-rules create allow-https \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:443 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=https-server 2>/dev/null || echo "  HTTPS rule already exists"
    
    print_status "Windows VM created successfully!"
    echo ""
    echo "To set Windows password, run:"
    echo "  gcloud compute reset-windows-password $WINDOWS_VM --zone=us-east4-a"
fi

# ============================================
# Task 3: Create a custom virtual machine
# ============================================
print_status "Task 3: Creating custom virtual machine..."

CUSTOM_VM="custom-vm"
echo "Creating custom VM: $CUSTOM_VM (2 vCPUs, 4 GB memory)..."

if gcloud compute instances describe $CUSTOM_VM --zone=us-east4-a &>/dev/null; then
    echo "  $CUSTOM_VM already exists, skipping..."
else
    gcloud compute instances create $CUSTOM_VM \
        --zone=us-east4-a \
        --custom-cpu=2 \
        --custom-memory=4GB \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard
    
    print_status "Custom VM created successfully!"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "Lab Completion Summary"
echo "=========================================="

echo ""
echo "VM instances created:"
gcloud compute instances list --sort-by=ZONE

echo ""
echo "=========================================="
print_status "All tasks completed successfully!"
echo "=========================================="
echo ""
echo "VMs Created:"
echo "1. utility-vm (e2-medium, no external IP) - for admin tasks"
echo "2. windows-vm (e2-standard-2, Windows Server 2016) - with HTTP/HTTPS"
echo "3. custom-vm (2 vCPUs, 4GB RAM, Debian 12) - custom configuration"
echo ""
echo "To connect to VMs:"
echo "  SSH to Debian VMs:"
echo "    gcloud compute ssh utility-vm --zone=us-east4-a"
echo "    gcloud compute ssh custom-vm --zone=us-east4-a"
echo ""
echo "  Set Windows password:"
echo "    gcloud compute reset-windows-password windows-vm --zone=us-east4-a"
echo ""
