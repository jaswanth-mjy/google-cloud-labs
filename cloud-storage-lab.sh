#!/bin/bash

# Cloud Storage Lab Automation Script
# This script automates Cloud Storage operations including ACLs, CSEK, lifecycle, and versioning

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

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Cloud Storage Lab${RESET}"

# Set project ID
PROJECT_ID="qwiklabs-gcp-04-17325fba2b5c"
export BUCKET_NAME_1="${PROJECT_ID}-bucket"
export REGION="us-east4"

echo "${CYAN}Using Project ID: $PROJECT_ID${RESET}"
echo "${CYAN}Bucket Name: $BUCKET_NAME_1${RESET}"

# Task 1: Preparation - Create bucket and download sample file
echo ""
echo "${YELLOW}${BOLD}Task 1: Creating Cloud Storage bucket and downloading sample file...${RESET}"

# Create bucket
if ! gcloud storage buckets describe gs://$BUCKET_NAME_1 &>/dev/null; then
    echo "Creating bucket: $BUCKET_NAME_1"
    gsutil mb -l $REGION -b off gs://$BUCKET_NAME_1
    echo "${GREEN}✓ Bucket created with fine-grained access control${RESET}"
else
    echo "${GREEN}✓ Bucket already exists${RESET}"
fi

# Download sample file
echo "Downloading sample file..."
curl -s https://hadoop.apache.org/docs/current/hadoop-project-dist/hadoop-common/ClusterSetup.html > setup.html

# Make copies
cp setup.html setup2.html
cp setup.html setup3.html

echo "${GREEN}✓ Sample file downloaded and copies created${RESET}"

# Task 2: Access Control Lists (ACLs)
echo ""
echo "${YELLOW}${BOLD}Task 2: Configuring Access Control Lists (ACLs)...${RESET}"

# Copy file to bucket
echo "Uploading setup.html to bucket..."
gcloud storage cp setup.html gs://$BUCKET_NAME_1/

# Get default ACL
echo "Getting default ACL..."
gsutil acl get gs://$BUCKET_NAME_1/setup.html > acl.txt
cat acl.txt

# Set to private
echo "Setting ACL to private..."
gsutil acl set private gs://$BUCKET_NAME_1/setup.html
gsutil acl get gs://$BUCKET_NAME_1/setup.html > acl2.txt
cat acl2.txt

# Make publicly readable
echo "Making file publicly readable..."
gsutil acl ch -u AllUsers:R gs://$BUCKET_NAME_1/setup.html
gsutil acl get gs://$BUCKET_NAME_1/setup.html > acl3.txt
cat acl3.txt

echo "${GREEN}✓ ACL configured - file is now publicly readable${RESET}"

# Delete local file and copy back
rm setup.html
gcloud storage cp gs://$BUCKET_NAME_1/setup.html setup.html
echo "${GREEN}✓ File recovered from bucket${RESET}"

# Task 3: Customer-Supplied Encryption Keys (CSEK)
echo ""
echo "${YELLOW}${BOLD}Task 3: Configuring Customer-Supplied Encryption Keys (CSEK)...${RESET}"

# Generate CSEK key
echo "Generating CSEK key..."
CSEK_KEY=$(python3 -c 'import base64; import os; print(base64.encodebytes(os.urandom(32)).decode().strip())')
echo "Generated CSEK key: $CSEK_KEY"

# Modify .boto file
echo "Configuring .boto file..."
if [ ! -f ~/.boto ]; then
    gsutil config -n
fi

# Backup original .boto
cp ~/.boto ~/.boto.backup

# Update .boto with encryption key
sed -i "s/#encryption_key=/encryption_key=$CSEK_KEY/" ~/.boto
sed -i "s/encryption_key=$/encryption_key=$CSEK_KEY/" ~/.boto

echo "${GREEN}✓ CSEK key configured in .boto file${RESET}"

# Upload encrypted files
echo "Uploading encrypted files..."
gsutil cp setup2.html gs://$BUCKET_NAME_1/
gsutil cp setup3.html gs://$BUCKET_NAME_1/

echo "${GREEN}✓ Encrypted files uploaded (setup2.html, setup3.html)${RESET}"

# Verify encryption by downloading
rm setup*
gsutil cp gs://$BUCKET_NAME_1/setup* ./
cat setup.html > /dev/null 2>&1 && echo "${GREEN}✓ setup.html decrypted successfully${RESET}"
cat setup2.html > /dev/null 2>&1 && echo "${GREEN}✓ setup2.html decrypted successfully${RESET}"
cat setup3.html > /dev/null 2>&1 && echo "${GREEN}✓ setup3.html decrypted successfully${RESET}"

# Task 4: Rotate CSEK Keys
echo ""
echo "${YELLOW}${BOLD}Task 4: Rotating CSEK keys...${RESET}"

# Move current encryption key to decryption key
OLD_KEY=$CSEK_KEY
sed -i "s/^encryption_key=/#encryption_key=$OLD_KEY/" ~/.boto
sed -i "s/#decryption_key1=/decryption_key1=$OLD_KEY/" ~/.boto
sed -i "s/decryption_key1=$/decryption_key1=$OLD_KEY/" ~/.boto

# Generate new CSEK key
NEW_KEY=$(python3 -c 'import base64; import os; print(base64.encodebytes(os.urandom(32)).decode().strip())')
echo "Generated new CSEK key: $NEW_KEY"

# Add new encryption key
sed -i "s/#encryption_key=.*/encryption_key=$NEW_KEY/" ~/.boto

echo "${GREEN}✓ CSEK key rotated${RESET}"

# Rewrite setup2.html with new key
echo "Rewriting setup2.html with new key..."
gsutil rewrite -k gs://$BUCKET_NAME_1/setup2.html

echo "${GREEN}✓ setup2.html rewritten with new key${RESET}"

# Comment out old decryption key
sed -i "s/^decryption_key1=/#decryption_key1=$OLD_KEY/" ~/.boto

# Test downloads
gsutil cp gs://$BUCKET_NAME_1/setup2.html recover2.html && echo "${GREEN}✓ setup2.html downloaded successfully (new key)${RESET}"
gsutil cp gs://$BUCKET_NAME_1/setup3.html recover3.html 2>&1 | grep -q "No decryption key" && echo "${YELLOW}⚠ setup3.html cannot be decrypted (old key)${RESET}" || echo "${GREEN}✓ setup3.html downloaded${RESET}"

# Task 5: Enable Lifecycle Management
echo ""
echo "${YELLOW}${BOLD}Task 5: Enabling lifecycle management...${RESET}"

# Check current lifecycle policy
echo "Current lifecycle policy:"
gsutil lifecycle get gs://$BUCKET_NAME_1

# Create lifecycle policy file
cat > life.json << 'EOF'
{
  "rule":
  [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 31}
    }
  ]
}
EOF

echo "Created lifecycle policy (delete after 31 days)"

# Set lifecycle policy
gsutil lifecycle set life.json gs://$BUCKET_NAME_1

# Verify lifecycle policy
echo "Verifying lifecycle policy:"
gsutil lifecycle get gs://$BUCKET_NAME_1

echo "${GREEN}✓ Lifecycle management enabled (objects will be deleted after 31 days)${RESET}"

# Task 6: Enable Versioning
echo ""
echo "${YELLOW}${BOLD}Task 6: Enabling versioning...${RESET}"

# Check versioning status
echo "Current versioning status:"
gsutil versioning get gs://$BUCKET_NAME_1

# Enable versioning
gsutil versioning set on gs://$BUCKET_NAME_1

# Verify versioning
echo "Verifying versioning:"
gsutil versioning get gs://$BUCKET_NAME_1

echo "${GREEN}✓ Versioning enabled${RESET}"

# Create multiple versions of setup.html
echo "Creating multiple versions of setup.html..."

# Check original size
ORIGINAL_SIZE=$(ls -l setup.html | awk '{print $5}')
echo "Original size: $ORIGINAL_SIZE bytes"

# Modify file (remove 5 lines) and upload version 1
head -n -5 setup.html > setup_temp.html
mv setup_temp.html setup.html
gcloud storage cp -v setup.html gs://$BUCKET_NAME_1
echo "${GREEN}✓ Version 1 uploaded${RESET}"

# Modify file again (remove 5 more lines) and upload version 2
head -n -5 setup.html > setup_temp.html
mv setup_temp.html setup.html
gcloud storage cp -v setup.html gs://$BUCKET_NAME_1
echo "${GREEN}✓ Version 2 uploaded${RESET}"

# List all versions
echo ""
echo "All versions of setup.html:"
gcloud storage ls -a gs://$BUCKET_NAME_1/setup.html

# Get the oldest version
VERSION_NAME=$(gcloud storage ls -a gs://$BUCKET_NAME_1/setup.html | head -n 1)
echo "Oldest version: $VERSION_NAME"

# Download oldest version
gcloud storage cp "$VERSION_NAME" recovered.txt

# Compare sizes
RECOVERED_SIZE=$(ls -l recovered.txt | awk '{print $5}')
CURRENT_SIZE=$(ls -l setup.html | awk '{print $5}')

echo ""
echo "Original size: $ORIGINAL_SIZE bytes"
echo "Current size: $CURRENT_SIZE bytes"
echo "Recovered size: $RECOVERED_SIZE bytes"

echo "${GREEN}✓ Original version recovered successfully${RESET}"

# Task 7: Synchronize a directory to a bucket
echo ""
echo "${YELLOW}${BOLD}Task 7: Synchronizing directory to bucket...${RESET}"

# Create nested directory structure
mkdir -p firstlevel/secondlevel
cp setup.html firstlevel/
cp setup.html firstlevel/secondlevel/

echo "Created directory structure:"
echo "firstlevel/"
echo "  ├── setup.html"
echo "  └── secondlevel/"
echo "      └── setup.html"

# Sync directory to bucket
echo ""
echo "Syncing directory to bucket..."
gsutil rsync -r ./firstlevel gs://$BUCKET_NAME_1/firstlevel

# List synced files
echo ""
echo "Synced files in bucket:"
gcloud storage ls -r gs://$BUCKET_NAME_1/firstlevel

echo "${GREEN}✓ Directory synchronized to bucket${RESET}"

# Display final summary
echo ""
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}${BOLD}Lab Completion Summary${RESET}"
echo "${GREEN}${BOLD}========================================${RESET}"
echo "${GREEN}✓ Task 1: Bucket created and sample file downloaded${RESET}"
echo "${GREEN}✓ Task 2: ACLs configured (private → public)${RESET}"
echo "${GREEN}✓ Task 3: CSEK encryption keys configured${RESET}"
echo "${GREEN}✓ Task 4: CSEK keys rotated successfully${RESET}"
echo "${GREEN}✓ Task 5: Lifecycle management enabled (31-day deletion)${RESET}"
echo "${GREEN}✓ Task 6: Versioning enabled and versions created${RESET}"
echo "${GREEN}✓ Task 7: Directory synchronized to bucket${RESET}"

echo ""
echo "${YELLOW}Key Information:${RESET}"
echo "${YELLOW}Bucket: ${GREEN}gs://$BUCKET_NAME_1${RESET}"
echo "${YELLOW}Region: ${GREEN}$REGION${RESET}"
echo "${YELLOW}CSEK Key (current): ${GREEN}$NEW_KEY${RESET}"
echo "${YELLOW}Lifecycle Policy: ${GREEN}Delete after 31 days${RESET}"
echo "${YELLOW}Versioning: ${GREEN}Enabled${RESET}"

echo ""
echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!!${RESET}"
