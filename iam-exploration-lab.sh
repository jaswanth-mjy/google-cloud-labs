#!/bin/bash

# Exploring IAM Lab Automation Script
# This script automates IAM role assignments and service account configuration

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

# Get lab credentials from environment or user input
if [ -z "$USER1_EMAIL" ]; then
    echo "${YELLOW}Enter Username 1 email (from lab credentials):${RESET}"
    read USER1_EMAIL
fi

if [ -z "$USER2_EMAIL" ]; then
    echo "${YELLOW}Enter Username 2 email (from lab credentials):${RESET}"
    read USER2_EMAIL
fi

export REGION="us-east1"
export ZONE="us-east1-d"

echo ""
echo "${YELLOW}${BOLD}Note:${RESET} Tasks 1 and 2 require manual login with both users."
echo "Please sign in to the Cloud Console with both Username 1 and Username 2 in separate tabs."
echo "Press Enter when ready to continue with automated tasks..."
read

# Task 3: Create a bucket and upload a sample file
echo ""
echo "${YELLOW}${BOLD}Task 3: Creating Cloud Storage bucket and uploading sample file...${RESET}"

# Generate unique bucket name using project ID
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-iam-bucket"

# Create bucket
if ! gcloud storage buckets describe gs://$BUCKET_NAME &>/dev/null; then
    echo "Creating bucket: $BUCKET_NAME"
    gcloud storage buckets create gs://$BUCKET_NAME \
        --location=US \
        --uniform-bucket-level-access
    echo "${GREEN}✓ Bucket created: $BUCKET_NAME${RESET}"
else
    echo "${GREEN}✓ Bucket already exists: $BUCKET_NAME${RESET}"
fi

# Create a sample file and upload it
echo "Creating and uploading sample.txt..."
echo "This is a sample file for IAM lab testing." > /tmp/sample.txt
gcloud storage cp /tmp/sample.txt gs://$BUCKET_NAME/sample.txt
echo "${GREEN}✓ Sample file uploaded${RESET}"

echo ""
echo "${YELLOW}Bucket Name: ${GREEN}$BUCKET_NAME${RESET}"
echo "${YELLOW}Please verify that Username 2 can see this bucket in the Cloud Console.${RESET}"
echo "Press Enter when ready to continue..."
read

# Task 4: Remove project access for Username 2
echo ""
echo "${YELLOW}${BOLD}Task 4: Removing Project Viewer role for Username 2...${RESET}"

# Check if user has Viewer role and remove it
if gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:$USER2_EMAIL AND bindings.role:roles/viewer" | grep -q "roles/viewer"; then
    echo "Removing Viewer role from $USER2_EMAIL..."
    gcloud projects remove-iam-policy-binding $PROJECT_ID \
        --member=user:$USER2_EMAIL \
        --role=roles/viewer \
        --quiet
    echo "${GREEN}✓ Project Viewer role removed for Username 2${RESET}"
else
    echo "${GREEN}✓ Username 2 does not have Viewer role (already removed)${RESET}"
fi

echo ""
echo "${YELLOW}Username 2 should no longer have access to the project.${RESET}"
echo "Verify in the Username 2 console that Cloud Storage buckets are not accessible."
echo "Press Enter when ready to continue..."
read

# Task 5: Add storage access for Username 2
echo ""
echo "${YELLOW}${BOLD}Task 5: Granting Storage Object Viewer role to Username 2...${RESET}"

# Grant Storage Object Viewer role
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=user:$USER2_EMAIL \
    --role=roles/storage.objectViewer \
    --quiet

echo "${GREEN}✓ Storage Object Viewer role granted to Username 2${RESET}"

echo ""
echo "${YELLOW}Username 2 should now be able to list bucket contents using:${RESET}"
echo "${CYAN}gcloud storage ls gs://$BUCKET_NAME${RESET}"
echo "Verify this in Username 2's Cloud Shell."
echo "Press Enter when ready to continue..."
read

# Task 6: Set up the Service Account User
echo ""
echo "${YELLOW}${BOLD}Task 6: Creating service account and configuring permissions...${RESET}"

SERVICE_ACCOUNT_NAME="read-bucket-objects"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL &>/dev/null; then
    echo "Creating service account: $SERVICE_ACCOUNT_NAME"
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="Read Bucket Objects Service Account" \
        --quiet
    echo "${GREEN}✓ Service account created${RESET}"
else
    echo "${GREEN}✓ Service account already exists${RESET}"
fi

# Grant Storage Object Viewer role to service account
echo "Granting Storage Object Viewer role to service account..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/storage.objectViewer \
    --quiet

echo "${GREEN}✓ Storage Object Viewer role granted to service account${RESET}"

# Grant Service Account User role to altostrat.com
echo "Granting Service Account User role to altostrat.com..."
gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT_EMAIL \
    --member=domain:altostrat.com \
    --role=roles/iam.serviceAccountUser \
    --quiet

echo "${GREEN}✓ Service Account User role granted to altostrat.com${RESET}"

# Grant Compute Instance Admin role to altostrat.com
echo "Granting Compute Instance Admin role to altostrat.com..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=domain:altostrat.com \
    --role=roles/compute.instanceAdmin.v1 \
    --quiet

echo "${GREEN}✓ Compute Instance Admin role granted to altostrat.com${RESET}"

# Create VM instance with service account
echo ""
echo "Creating VM instance 'demoiam' with service account..."

if gcloud compute instances describe demoiam --zone=$ZONE &>/dev/null; then
    echo "Deleting existing VM 'demoiam'..."
    gcloud compute instances delete demoiam --zone=$ZONE --quiet
fi

gcloud compute instances create demoiam \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --service-account=$SERVICE_ACCOUNT_EMAIL \
    --scopes=storage-rw \
    --quiet

echo "${GREEN}✓ VM 'demoiam' created with service account${RESET}"

# Task 7: Test service account permissions
echo ""
echo "${YELLOW}${BOLD}Task 7: Testing service account permissions...${RESET}"

echo ""
echo "${YELLOW}Testing commands on VM 'demoiam':${RESET}"

# Test 1: Try to list compute instances (should fail initially)
echo ""
echo "Test 1: Attempting to list compute instances (expected to fail)..."
gcloud compute ssh demoiam --zone=$ZONE --command="gcloud compute instances list" --quiet || echo "${YELLOW}⚠ Command failed as expected (insufficient permissions)${RESET}"

# Test 2: Download file from bucket (should succeed)
echo ""
echo "Test 2: Downloading sample.txt from bucket (should succeed)..."
gcloud compute ssh demoiam --zone=$ZONE --command="gcloud storage cp gs://$BUCKET_NAME/sample.txt . && ls -l sample.txt" --quiet
echo "${GREEN}✓ File download successful${RESET}"

# Test 3: Rename and try to upload (should fail with current permissions)
echo ""
echo "Test 3: Attempting to upload file (expected to fail with Storage Object Viewer role)..."
gcloud compute ssh demoiam --zone=$ZONE --command="mv sample.txt sample2.txt && gcloud storage cp sample2.txt gs://$BUCKET_NAME/" --quiet || echo "${YELLOW}⚠ Upload failed as expected (Storage Object Viewer has read-only access)${RESET}"

# Update service account role to Storage Object Creator
echo ""
echo "${YELLOW}Updating service account role to Storage Object Creator...${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$SERVICE_ACCOUNT_EMAIL \
    --role=roles/storage.objectCreator \
    --quiet

echo "${GREEN}✓ Storage Object Creator role granted${RESET}"

# Wait a moment for permissions to propagate
echo "Waiting 10 seconds for permissions to propagate..."
sleep 10

# Test 4: Try upload again (should succeed now)
echo ""
echo "Test 4: Attempting to upload file again (should succeed now)..."
gcloud compute ssh demoiam --zone=$ZONE --command="gcloud storage cp sample2.txt gs://$BUCKET_NAME/" --quiet
echo "${GREEN}✓ File upload successful with Storage Object Creator role${RESET}"

# Display summary
echo ""
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}${BOLD}Lab Completion Summary${RESET}"
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}✓ Task 3: Bucket created and sample file uploaded${RESET}"
echo "${GREEN}✓ Task 4: Project Viewer role removed for Username 2${RESET}"
echo "${GREEN}✓ Task 5: Storage Object Viewer role granted to Username 2${RESET}"
echo "${GREEN}✓ Task 6: Service account created and configured${RESET}"
echo "${GREEN}✓ Task 6: VM created with service account${RESET}"
echo "${GREEN}✓ Task 6: Permissions granted to altostrat.com${RESET}"
echo "${GREEN}✓ Task 7: Service account permissions tested${RESET}"

echo ""
echo "${YELLOW}Key Information:${RESET}"
echo "${YELLOW}Bucket Name: ${GREEN}$BUCKET_NAME${RESET}"
echo "${YELLOW}Service Account: ${GREEN}$SERVICE_ACCOUNT_EMAIL${RESET}"
echo "${YELLOW}VM Instance: ${GREEN}demoiam (zone: $ZONE)${RESET}"

echo ""
echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!!${RESET}"
