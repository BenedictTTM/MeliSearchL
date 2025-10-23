#!/bin/bash

# MeiliSearch Backup Script
# Automates the creation and management of MeiliSearch dumps

set -e

# Configuration
BACKUP_DIR="./backups"
MEILI_HOST="${MEILI_HOST:-http://localhost:7700}"
MEILI_KEY="${MEILI_MASTER_KEY}"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo -e "${GREEN}Starting MeiliSearch backup...${NC}"

# Create dump via API
echo "Creating dump..."
RESPONSE=$(curl -s -X POST "$MEILI_HOST/dumps" \
  -H "X-Meili-API-Key: $MEILI_KEY")

TASK_UID=$(echo "$RESPONSE" | jq -r '.taskUid')

if [ "$TASK_UID" == "null" ]; then
    echo -e "${RED}Failed to create dump. Response: $RESPONSE${NC}"
    exit 1
fi

echo -e "${GREEN}Task created with UID: $TASK_UID${NC}"

# Poll for completion
MAX_WAIT=300  # 5 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATUS_RESPONSE=$(curl -s -X GET "$MEILI_HOST/tasks/$TASK_UID" \
      -H "X-Meili-API-Key: $MEILI_KEY")
    
    STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
    
    case "$STATUS" in
        "succeeded")
            echo -e "${GREEN}Dump created successfully!${NC}"
            break
            ;;
        "failed")
            echo -e "${RED}Dump creation failed!${NC}"
            echo "$STATUS_RESPONSE" | jq '.error'
            exit 1
            ;;
        "enqueued"|"processing")
            echo -e "${YELLOW}Status: $STATUS... waiting${NC}"
            sleep 5
            ELAPSED=$((ELAPSED + 5))
            ;;
        *)
            echo -e "${RED}Unknown status: $STATUS${NC}"
            exit 1
            ;;
    esac
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Timeout waiting for dump to complete${NC}"
    exit 1
fi

# Find the most recent dump file
DUMP_FILE=$(ls -t ./data/dumps/*.dump 2>/dev/null | head -1)

if [ -z "$DUMP_FILE" ]; then
    echo -e "${RED}No dump file found in ./data/dumps/${NC}"
    exit 1
fi

# Copy and compress dump
BACKUP_FILE="$BACKUP_DIR/meili_dump_$DATE.dump"
echo "Copying dump to $BACKUP_FILE..."
cp "$DUMP_FILE" "$BACKUP_FILE"

echo "Compressing backup..."
gzip "$BACKUP_FILE"

BACKUP_SIZE=$(du -h "$BACKUP_FILE.gz" | cut -f1)
echo -e "${GREEN}Backup completed: $BACKUP_FILE.gz ($BACKUP_SIZE)${NC}"

# Clean up old backups
echo "Removing backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "meili_dump_*.dump.gz" -mtime +$RETENTION_DAYS -delete

# Optional: Upload to cloud storage (uncomment and configure)
# aws s3 cp "$BACKUP_FILE.gz" "s3://your-bucket/meilisearch-backups/"
# gcloud storage cp "$BACKUP_FILE.gz" "gs://your-bucket/meilisearch-backups/"

echo -e "${GREEN}Backup process complete!${NC}"
