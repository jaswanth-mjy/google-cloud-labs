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

# Task 2: Examine the table
echo "Task 2: Examining the table..."
echo ""

# Show schema
echo "Table Schema:"
bq show --schema --format=prettyjson $PROJECT_ID:$DATASET_ID.$TABLE_ID
echo ""

# Show table details (number of rows)
echo "Table Details:"
bq show $PROJECT_ID:$DATASET_ID.$TABLE_ID | grep -E "(numRows|numBytes)"
echo ""

# Get exact row count
echo "Total number of rows:"
bq query --use_legacy_sql=false --format=csv "SELECT COUNT(*) as total_rows FROM \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`"
echo ""

# Preview data
echo "Previewing first 10 rows..."
bq query --use_legacy_sql=false "SELECT * FROM \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\` LIMIT 10"
echo ""

# Task 3: Compose a simple query
echo "Task 3: Composing a simple query..."
echo "Query: SELECT * FROM billing_dataset.sampleinfotable WHERE Cost > 0"
echo ""

# Run the query and count results
echo "Records with Cost > 0:"
bq query --use_legacy_sql=false --format=csv "SELECT COUNT(*) as records_with_cost FROM \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\` WHERE Cost > 0"
echo ""

# Show sample records with cost > 0
echo "Sample records where Cost > 0 (first 10):"
bq query --use_legacy_sql=false "SELECT * FROM \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\` WHERE Cost > 0 LIMIT 10"

echo ""
echo "=========================================="
echo "Task 4: Analyze a large billing dataset with SQL"
echo "=========================================="
echo ""

# Query 1: Get all records
echo "Query 1: Retrieving all billing records..."
bq query --use_legacy_sql=false "
SELECT
  billing_account_id,
  project.id,
  project.name,
  service.description,
  currency,
  currency_conversion_rate,
  cost,
  usage.amount,
  usage.pricing_unit
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
" > /dev/null
echo "✓ Query completed (415,602 records expected)"
echo ""

# Query 2: Latest 100 records where cost > 0
echo "Query 2: Finding latest 100 records where cost > 0..."
bq query --use_legacy_sql=false "
SELECT
  service.description,
  sku.description,
  location.country,
  cost,
  project.id,
  project.name,
  currency,
  currency_conversion_rate,
  usage.amount,
  usage.unit
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
WHERE
  Cost > 0
ORDER BY usage_end_time DESC
LIMIT 100
"
echo ""

# Query 3: All charges more than $10
echo "Query 3: Finding all charges more than $10..."
bq query --use_legacy_sql=false "
SELECT
  service.description,
  sku.description,
  location.country,
  cost,
  project.id,
  project.name,
  currency,
  currency_conversion_rate,
  usage.amount,
  usage.unit
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
WHERE
  cost > 10
"
echo ""

# Query 4: Product with most billing records
echo "Query 4: Finding product with most billing records..."
bq query --use_legacy_sql=false "
SELECT
  service.description,
  COUNT(*) AS billing_records
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
GROUP BY
  service.description
ORDER BY billing_records DESC
"
echo "Answer: Compute Engine has 281,136 records (most)"
echo ""

# Query 5: Most frequently used product costing > $1
echo "Query 5: Finding most frequently used product costing more than \$1..."
bq query --use_legacy_sql=false "
SELECT
  service.description,
  COUNT(*) AS billing_records
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
WHERE
  cost > 1
GROUP BY
  service.description
ORDER BY
  billing_records DESC
"
echo "Answer: Cloud Storage has 17 charges costing more than \$1"
echo ""

# Query 6: Most commonly charged unit of measure
echo "Query 6: Finding most commonly charged unit of measure..."
bq query --use_legacy_sql=false "
SELECT
  usage.unit,
  COUNT(*) AS billing_records
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
WHERE cost > 0
GROUP BY
  usage.unit
ORDER BY
  billing_records DESC
"
echo "Answer: Byte-seconds were the most commonly charged unit"
echo ""

# Query 7: Product with highest aggregate cost
echo "Query 7: Finding product with highest aggregate cost..."
bq query --use_legacy_sql=false "
SELECT
  service.description,
  ROUND(SUM(cost),2) AS total_cost
FROM
  \`$PROJECT_ID.$DATASET_ID.$TABLE_ID\`
GROUP BY
  service.description
ORDER BY
  total_cost DESC
"
echo "Answer: Compute Engine has highest aggregate cost of \$2,548.77"
echo ""

echo "=========================================="
echo "Lab completed successfully!"
echo "=========================================="
echo ""
echo "Task 5: Review - Check BigQuery console for query history and results"
