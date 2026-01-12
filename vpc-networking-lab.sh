#!/bin/bash

# VPC Networking Lab - Automated Script
# This script completes all tasks in the VPC Networking lab
# It skips already completed tasks

echo "=========================================="
echo "VPC Networking Lab - Automated Completion"
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
# Task 1: Delete default network (if exists)
# ============================================
print_status "Task 1: Cleaning up default network..."

# Delete default firewall rules
echo "Deleting default firewall rules..."
gcloud compute firewall-rules delete default-allow-icmp --quiet 2>/dev/null || echo "  Already deleted or not found"
gcloud compute firewall-rules delete default-allow-internal --quiet 2>/dev/null || echo "  Already deleted or not found"
gcloud compute firewall-rules delete default-allow-rdp --quiet 2>/dev/null || echo "  Already deleted or not found"
gcloud compute firewall-rules delete default-allow-ssh --quiet 2>/dev/null || echo "  Already deleted or not found"

# Delete default network
echo "Deleting default network..."
gcloud compute networks delete default --quiet 2>/dev/null || echo "  Already deleted or not found"

print_status "Task 1 completed!"

# ============================================
# Task 2: Create auto mode network
# ============================================
print_status "Task 2: Creating auto mode network with firewall rules..."

# Enable necessary APIs
echo "Enabling required APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable iap.googleapis.com
gcloud services enable networkmanagement.googleapis.com

# Create auto mode network
echo "Creating mynetwork (auto mode)..."
gcloud compute networks create mynetwork --subnet-mode=auto 2>/dev/null || echo "  Network already exists, skipping..."

# Create firewall rules for mynetwork
echo "Creating firewall rules for mynetwork..."

# Allow ICMP
gcloud compute firewall-rules create mynetwork-allow-icmp \
    --network=mynetwork \
    --direction=INGRESS \
    --priority=65534 \
    --action=ALLOW \
    --rules=icmp \
    --source-ranges=0.0.0.0/0 2>/dev/null || echo "  mynetwork-allow-icmp already exists"

# Allow internal traffic
gcloud compute firewall-rules create mynetwork-allow-custom \
    --network=mynetwork \
    --direction=INGRESS \
    --priority=65534 \
    --action=ALLOW \
    --rules=all \
    --source-ranges=10.128.0.0/9 2>/dev/null || echo "  mynetwork-allow-custom already exists"

# Allow RDP
gcloud compute firewall-rules create mynetwork-allow-rdp \
    --network=mynetwork \
    --direction=INGRESS \
    --priority=65534 \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges=0.0.0.0/0 2>/dev/null || echo "  mynetwork-allow-rdp already exists"

# Allow SSH
gcloud compute firewall-rules create mynetwork-allow-ssh \
    --network=mynetwork \
    --direction=INGRESS \
    --priority=65534 \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0 2>/dev/null || echo "  mynetwork-allow-ssh already exists"

# Allow IAP SSH access
echo "Creating IAP firewall rule..."
gcloud compute firewall-rules create allow-iap-ssh \
    --network=mynetwork \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=iap-gce 2>/dev/null || echo "  allow-iap-ssh already exists"

# Create VM instances
echo "Creating mynet-us-vm in us-central1-c..."
if gcloud compute instances describe mynet-us-vm --zone=us-central1-c &>/dev/null; then
    echo "  mynet-us-vm already exists, skipping..."
else
    gcloud compute instances create mynet-us-vm \
        --zone=us-central1-c \
        --machine-type=e2-medium \
        --network=mynetwork \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard \
        --tags=iap-gce
fi

echo "Creating mynet-notus-vm in asia-east1-a..."
if gcloud compute instances describe mynet-notus-vm --zone=asia-east1-a &>/dev/null; then
    echo "  mynet-notus-vm already exists, skipping..."
else
    gcloud compute instances create mynet-notus-vm \
        --zone=asia-east1-a \
        --machine-type=e2-medium \
        --network=mynetwork \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard \
        --tags=iap-gce
fi

print_status "Task 2 completed! VMs are being created..."

# Wait for instances to be ready
echo "Waiting for instances to be ready..."
sleep 30

# Convert auto mode to custom mode
echo "Converting mynetwork from auto mode to custom mode..."
gcloud compute networks update mynetwork --switch-to-custom-subnet-mode

print_status "Network converted to custom mode!"

# ============================================
# Task 3: Create custom mode networks
# ============================================
print_status "Task 3: Creating custom mode networks..."

# Create managementnet network
echo "Creating managementnet network..."
gcloud compute networks create managementnet --subnet-mode=custom 2>/dev/null || echo "  managementnet already exists"

echo "Creating managementsubnet-us..."
gcloud compute networks subnets create managementsubnet-us \
    --network=managementnet \
    --region=us-central1 \
    --range=10.240.0.0/20 2>/dev/null || echo "  managementsubnet-us already exists"

# Create privatenet network
echo "Creating privatenet network..."
gcloud compute networks create privatenet --subnet-mode=custom 2>/dev/null || echo "  privatenet already exists"

echo "Creating privatesubnet-us..."
gcloud compute networks subnets create privatesubnet-us \
    --network=privatenet \
    --region=us-central1 \
    --range=172.16.0.0/24 2>/dev/null || echo "  privatesubnet-us already exists"

echo "Creating privatesubnet-notus..."
gcloud compute networks subnets create privatesubnet-notus \
    --network=privatenet \
    --region=asia-east1 \
    --range=172.20.0.0/20 2>/dev/null || echo "  privatesubnet-notus already exists"

# Create firewall rules for managementnet
echo "Creating firewall rules for managementnet..."
gcloud compute firewall-rules create managementnet-allow-icmp-ssh-rdp \
    --network=managementnet \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=icmp,tcp:22,tcp:3389 \
    --source-ranges=0.0.0.0/0 2>/dev/null || echo "  managementnet-allow-icmp-ssh-rdp already exists"

# Create firewall rules for privatenet
echo "Creating firewall rules for privatenet..."
gcloud compute firewall-rules create privatenet-allow-icmp-ssh-rdp \
    --network=privatenet \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=icmp,tcp:22,tcp:3389 \
    --source-ranges=0.0.0.0/0 2>/dev/null || echo "  privatenet-allow-icmp-ssh-rdp already exists"

# Create VM instances for managementnet
echo "Creating managementnet-us-vm..."
if gcloud compute instances describe managementnet-us-vm --zone=us-central1-c &>/dev/null; then
    echo "  managementnet-us-vm already exists, skipping..."
else
    gcloud compute instances create managementnet-us-vm \
        --zone=us-central1-c \
        --machine-type=e2-micro \
        --subnet=managementsubnet-us \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard
fi

# Create VM instance for privatenet
echo "Creating privatenet-us-vm..."
if gcloud compute instances describe privatenet-us-vm --zone=us-central1-c &>/dev/null; then
    echo "  privatenet-us-vm already exists, skipping..."
else
    gcloud compute instances create privatenet-us-vm \
        --zone=us-central1-c \
        --machine-type=e2-micro \
        --subnet=privatesubnet-us \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard
fi

print_status "Task 3 completed! All custom networks and VMs created!"

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "Lab Completion Summary"
echo "=========================================="

echo ""
echo "Networks created:"
gcloud compute networks list

echo ""
echo "Subnets created:"
gcloud compute networks subnets list --sort-by=NETWORK

echo ""
echo "Firewall rules created:"
gcloud compute firewall-rules list --sort-by=NETWORK

echo ""
echo "VM instances created:"
gcloud compute instances list --sort-by=ZONE

echo ""
echo "=========================================="
print_status "All tasks completed successfully!"
echo "=========================================="
echo ""
echo "Key Points:"
echo "1. Default network has been deleted"
echo "2. mynetwork (auto mode → custom mode) created with VMs in us-central1 and asia-east1"
echo "3. managementnet (custom mode) created with subnet and VM in us-central1"
echo "4. privatenet (custom mode) created with subnets in us-central1 and asia-east1"
echo ""
echo "Note: VMs in different VPC networks cannot communicate via internal IP"
echo "      but can communicate via external IP (if firewall rules allow)"
echo ""
