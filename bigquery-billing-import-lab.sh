#!/bin/bash

# BigQuery Billing Data Import Lab
# This script automates the process of creating a BigQuery dataset and importing billing data

set -e

# Variables
PROJECT_ID=$(gcloud config get-value project)
DATASET_ID="billing_dataset"
TABLE_ID="sampleinfotable"
SOURCE_FILE="gs://cloud-training/archinfra/BillingExport-2020-09-18.avro"

echo "=========================================="
echo "BigQuery Billing Data Import Lab"
echo "=========================================="
echo "Project ID: $PROJECT_ID"
echo ""

# Task 1: Create BigQuery dataset
echo "Task 1: Creating BigQuery dataset..."
echo "- Dataset ID: $DATASET_ID"
echo "- Location: US"
echo "- Default table expiration: 1 day (86400 seconds)"

bq --location=US mk \
    --dataset \
    --default_table_expiration 86400 \
    --description "Billing dataset for lab" \
    $PROJECT_ID:$DATASET_ID

echo "✓ Dataset created successfully."
echo ""

# Verify dataset creation
echo "Verifying dataset creation..."
bq show $PROJECT_ID:$DATASET_ID
echo ""

# Task 2: Create table and import data from Cloud Storage
echo "Task 2: Creating table and importing data..."
echo "- Table name: $TABLE_ID"
echo "- Source: $SOURCE_FILE"
echo "- Format: AVRO"

bq load \
    --source_format=AVRO \
    $PROJECT_ID:$DATASET_ID.$TABLE_ID \
    $SOURCE_FILE

echo "✓ Table created and data imported successfully."
echo ""

# Verify table creation
echo "Verifying table creation..."
bq show $PROJECT_ID:$DATASET_ID.$TABLE_ID
echo ""

# Show table preview
echo "Previewing first 10 rows..."
bq query --use_legacy_sql=false "SELECT * FROM \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\` LIMIT 10"

echo ""
echo "=========================================="
echo "Lab completed successfully!"
echo "=========================================="
echo ""
echo "You can query the table using:"
echo "  bq query 'SELECT * FROM $DATASET_ID.$TABLE_ID LIMIT 10'"
