#!/bin/bash

# Define color variables
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}

echo "${RANDOM_TEXT_COLOR}${BOLD}Starting Dataproc Setup${RESET}"

# ==================== STEP 1: Set Compute Zone & Region ====================
echo "${BOLD}${BLUE}Step 1: Setting Compute Zone and Region${RESET}"
export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "${GREEN}Zone: $ZONE${RESET}"
echo "${GREEN}Region: $REGION${RESET}"

# ==================== STEP 2: Get Project Information ====================
echo "${BOLD}${YELLOW}Step 2: Getting Project Information${RESET}"
export PROJECT_ID="qwiklabs-gcp-03-cbba027db714"
export PROJECT_NUMBER="$(gcloud projects describe $PROJECT_ID --format='get(projectNumber)')"

echo "${GREEN}Project ID: $PROJECT_ID${RESET}"
echo "${GREEN}Project Number: $PROJECT_NUMBER${RESET}"

# ==================== STEP 3: Enable Cloud Dataproc API ====================
echo "${BOLD}${MAGENTA}Step 3: Enabling Cloud Dataproc API${RESET}"
gcloud services enable dataproc.googleapis.com

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Cloud Dataproc API is now enabled${RESET}"
else
  echo "${RED}✗ Failed to enable Cloud Dataproc API${RESET}"
  exit 1
fi

# ==================== STEP 4: Grant Storage Admin Role ====================
echo "${BOLD}${CYAN}Step 4: Granting Storage Admin Role to Compute Service Account${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role roles/storage.objectAdmin \
  --condition=None

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Storage Admin role granted${RESET}"
else
  echo "${RED}✗ Failed to grant Storage Admin role${RESET}"
fi

# ==================== STEP 5: Grant Dataproc Worker Role ====================
echo "${BOLD}${RED}Step 5: Granting Dataproc Worker Role to Compute Service Account${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role roles/dataproc.worker \
  --condition=None

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Dataproc Worker role granted${RESET}"
else
  echo "${RED}✗ Failed to grant Dataproc Worker role${RESET}"
fi

# ==================== STEP 6: Create Dataproc Cluster ====================
echo "${BOLD}${BLUE}Step 6: Creating Dataproc Cluster (example-cluster)${RESET}"

# Check if cluster already exists
CLUSTER_EXISTS=$(gcloud dataproc clusters describe example-cluster --region us-west1 2>/dev/null)

if [ $? -eq 0 ]; then
  echo "${YELLOW}Cluster 'example-cluster' already exists${RESET}"
  CLUSTER_STATUS=$(gcloud dataproc clusters describe example-cluster --region us-west1 --format="value(status.state)")
  echo "${CYAN}Current Status: $CLUSTER_STATUS${RESET}"
  echo -e "\n${BOLD}${MAGENTA}Do you want to:${RESET}"
  echo "  1) Delete and recreate the cluster"
  echo "  2) Use the existing cluster"
  read -p "Enter choice (1 or 2): " choice
  
  if [ "$choice" = "1" ]; then
    echo "${YELLOW}Deleting existing cluster...${RESET}"
    gcloud dataproc clusters delete example-cluster --region us-west1 --quiet
    if [ $? -eq 0 ]; then
      echo "${GREEN}✓ Cluster deleted${RESET}"
      echo -e "\n${YELLOW}Creating new cluster (this may take several minutes)...${RESET}"
      gcloud dataproc clusters create example-cluster \
        --region us-west1 \
        --zone us-west1-b \
        --master-machine-type e2-standard-2 \
        --master-boot-disk-size 30 \
        --num-workers 2 \
        --worker-machine-type e2-standard-2 \
        --worker-boot-disk-size 30 \
        --image-version 2.2-debian12 \
        --project $PROJECT_ID \
        --enable-component-gateway
      
      if [ $? -eq 0 ]; then
        echo "${GREEN}✓ Cluster creation initiated successfully${RESET}"
      else
        echo "${RED}✗ Failed to create cluster${RESET}"
        exit 1
      fi
    else
      echo "${RED}✗ Failed to delete cluster${RESET}"
      exit 1
    fi
  else
    echo "${GREEN}✓ Using existing cluster${RESET}"
  fi
else
  echo "${YELLOW}Cluster does not exist. Creating new cluster...${RESET}"
  gcloud dataproc clusters create example-cluster \
    --region us-west1 \
    --zone us-west1-b \
    --master-machine-type e2-standard-2 \
    --master-boot-disk-size 30 \
    --num-workers 2 \
    --worker-machine-type e2-standard-2 \
    --worker-boot-disk-size 30 \
    --image-version 2.2-debian12 \
    --project $PROJECT_ID \
    --enable-component-gateway
  
  if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Cluster creation initiated successfully${RESET}"
  else
    echo "${RED}✗ Failed to create cluster${RESET}"
    exit 1
  fi
fi

# ==================== STEP 7: Verify Cluster Status ====================
echo "${BOLD}${GREEN}Step 7: Verifying Cluster Status${RESET}"
gcloud dataproc clusters describe example-cluster \
  --region us-west1 \
  --format="value(status.state)"

echo "${CYAN}Cluster Status:${RESET}"
gcloud dataproc clusters list --region us-west1 --format="table(name,status.state,location)"

# ==================== COMPLETION MESSAGE ====================
echo -e "\n"
echo "${BOLD}${GREEN}========================================${RESET}"
echo "${BOLD}${GREEN}Dataproc Cluster Setup Complete!${RESET}"
echo "${BOLD}${GREEN}========================================${RESET}"
echo -e "\n"
echo "${YELLOW}Cluster Details:${RESET}"
echo "  Name: example-cluster"
echo "  Region: us-west1"
echo "  Zone: us-west1-b"
echo "  Master Machine: e2-standard-2 (30 GB disk)"
echo "  Workers: 2 x e2-standard-2 (30 GB disk each)"
echo "  Image Version: 2.2-debian12"
echo -e "\n"

# ==================== TASK 2: SUBMIT A SPARK JOB ====================
echo "${BOLD}${MAGENTA}========================================${RESET}"
echo "${BOLD}${MAGENTA}TASK 2: Submitting Spark Job${RESET}"
echo "${BOLD}${MAGENTA}========================================${RESET}"
echo -e "\n"
echo "${BOLD}${BLUE}Submitting SparkPi job to estimate Pi using Monte Carlo method${RESET}"
echo "${YELLOW}Job Configuration:${RESET}"
echo "  Region: us-west1"
echo "  Cluster: example-cluster"
echo "  Job Type: Spark"
echo "  Main Class: org.apache.spark.examples.SparkPi"
echo "  Jar File: file:///usr/lib/spark/examples/jars/spark-examples.jar"
echo "  Arguments: 1000 (number of tasks)"
echo -e "\n"

JOB_ID=$(gcloud dataproc jobs submit spark \
  --cluster example-cluster \
  --region us-west1 \
  --class org.apache.spark.examples.SparkPi \
  --jars file:///usr/lib/spark/examples/jars/spark-examples.jar \
  -- 1000 \
  --format="value(reference.jobId)")

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Job submitted successfully${RESET}"
  echo "${CYAN}Job ID: $JOB_ID${RESET}"
else
  echo "${RED}✗ Failed to submit job${RESET}"
  exit 1
fi

# Wait for job to complete
echo -e "\n"
echo "${BOLD}${YELLOW}Waiting for job to complete (this may take a few minutes)...${RESET}"
gcloud dataproc jobs wait $JOB_ID --region us-west1

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Job completed successfully${RESET}"
else
  echo "${RED}✗ Job failed or was cancelled${RESET}"
fi

# ==================== TASK 3: VIEW JOB OUTPUT ====================
echo -e "\n"
echo "${BOLD}${CYAN}========================================${RESET}"
echo "${BOLD}${CYAN}TASK 3: Viewing Job Output${RESET}"
echo "${BOLD}${CYAN}========================================${RESET}"
echo -e "\n"
echo "${BOLD}${BLUE}Job Status and Details:${RESET}"
gcloud dataproc jobs describe $JOB_ID --region us-west1 \
  --format="table(reference.jobId,status.state,driverOutputResourceUri)"

echo -e "\n"
echo "${YELLOW}Fetching job output (showing last 50 lines):${RESET}"
gsutil cat $(gcloud dataproc jobs describe $JOB_ID --region us-west1 --format="value(driverOutputResourceUri)") 2>/dev/null | tail -50

echo -e "\n"

# ==================== TASK 4: UPDATE CLUSTER WORKER COUNT ====================
echo "${BOLD}${RED}========================================${RESET}"
echo "${BOLD}${RED}TASK 4: Updating Cluster Worker Count${RESET}"
echo "${BOLD}${RED}========================================${RESET}"
echo -e "\n"
echo "${BOLD}${BLUE}Updating example-cluster from 2 workers to 4 workers${RESET}"
echo "${YELLOW}This may take a few minutes...${RESET}"

gcloud dataproc clusters update example-cluster \
  --region us-west1 \
  --num-workers 4

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Cluster updated successfully${RESET}"
else
  echo "${RED}✗ Failed to update cluster${RESET}"
fi

echo -e "\n"
echo "${BOLD}${GREEN}Updated Cluster Configuration:${RESET}"
gcloud dataproc clusters describe example-cluster \
  --region us-west1 \
  --format="table(name,config.masterConfig.machineTypeUri,config.workerConfig.numInstances,config.workerConfig.machineTypeUri,status.state)"

echo -e "\n"

# ==================== OPTIONAL: RESUBMIT JOB WITH UPDATED CLUSTER ====================
echo "${BOLD}${MAGENTA}========================================${RESET}"
echo "${BOLD}${MAGENTA}Optional: Resubmitting Job with Updated Cluster${RESET}"
echo "${BOLD}${MAGENTA}========================================${RESET}"
echo -e "\n"
echo "${BOLD}${BLUE}Submitting another SparkPi job with 4-worker cluster${RESET}"

JOB_ID_2=$(gcloud dataproc jobs submit spark \
  --cluster example-cluster \
  --region us-west1 \
  --class org.apache.spark.examples.SparkPi \
  --jars file:///usr/lib/spark/examples/jars/spark-examples.jar \
  -- 1000 \
  --format="value(reference.jobId)")

if [ $? -eq 0 ]; then
  echo "${GREEN}✓ Second job submitted successfully${RESET}"
  echo "${CYAN}Job ID: $JOB_ID_2${RESET}"
  
  echo -e "\n"
  echo "${YELLOW}Waiting for job to complete...${RESET}"
  gcloud dataproc jobs wait $JOB_ID_2 --region us-west1
  
  if [ $? -eq 0 ]; then
    echo "${GREEN}✓ Second job completed successfully${RESET}"
    echo -e "\n"
    echo "${YELLOW}Job comparison:${RESET}"
    gcloud dataproc jobs list --region us-west1 --format="table(reference.jobId,status.state,yarnApplicationsId)" --limit 2
  fi
else
  echo "${RED}✗ Failed to submit second job${RESET}"
fi

# ==================== FINAL SUMMARY ====================
echo -e "\n"
echo "${BOLD}${GREEN}========================================${RESET}"
echo "${BOLD}${GREEN}All Tasks Completed Successfully!${RESET}"
echo "${BOLD}${GREEN}========================================${RESET}"
echo -e "\n"
echo "${CYAN}Summary:${RESET}"
echo "  ✓ Task 1: Created Dataproc cluster (example-cluster)"
echo "  ✓ Task 2: Submitted Spark job (SparkPi)"
echo "  ✓ Task 3: Viewed job output"
echo "  ✓ Task 4: Updated cluster to 4 workers"
echo "  ✓ Task 5: Resubmitted job with updated cluster"
echo -e "\n"
echo "${YELLOW}Key Learnings:${RESET}"
echo "  • Managed Apache Spark helps process and transform vast data quantities"
echo "  • SparkPi uses Monte Carlo method to estimate Pi"
echo "  • Clusters can be scaled dynamically by updating worker count"
echo "  • Jobs can be monitored and their output retrieved programmatically"
echo -e "\n"
echo "${GREEN}Questions for self-assessment:${RESET}"
echo "  Q1: Which type of job was submitted? Answer: Spark (SparkPi)"
echo "  Q2: Does Managed Apache Spark help process vast data? Answer: True"
echo -e "\n"
