# MeiliSearch Setup for Sellr

Complete MeiliSearch deployment guide for the Sellr e-commerce platform.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Production Deployment](#production-deployment)
- [API Key Management](#api-key-management)
- [Index Configuration](#index-configuration)
- [Backup & Recovery](#backup--recovery)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## 🚀 Quick Start

### 1. Generate Master Key

```powershell
# Windows PowerShell
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))

# Or use online tool: https://www.random.org/strings/
```

### 2. Create .env File

```bash
cp .env.example .env
# Edit .env and replace MEILI_MASTER_KEY with your generated key
```

### 3. Start MeiliSearch

```bash
docker compose up -d
```

### 4. Verify Health

```powershell
curl http://localhost:7700/health
# Expected: {"status":"available"}
```

---

## 🏗️ Production Deployment

### Step 1: Secure Configuration

**docker-compose.prod.yml**:

```yaml
version: "3.8"
services:
  meilisearch:
    image: getmeili/meilisearch:v1.11
    container_name: sellr_meilisearch_prod
    restart: always
    environment:
      MEILI_MASTER_KEY: "${MEILI_MASTER_KEY}"
      MEILI_ENV: "production"
      MEILI_NO_ANALYTICS: "true"
      MEILI_HTTP_ADDR: "127.0.0.1:7700" # Only localhost
    volumes:
      - meili_data:/meili_data
    networks:
      - internal

volumes:
  meili_data:
    driver: local

networks:
  internal:
    driver: bridge
```

### Step 2: Reverse Proxy (Nginx + TLS)

**nginx.conf**:

```nginx
upstream meilisearch {
    server 127.0.0.1:7700;
}

server {
    listen 80;
    server_name search.sellr.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name search.sellr.com;

    # TLS certificates (use Certbot)
    ssl_certificate /etc/letsencrypt/live/search.sellr.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/search.sellr.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # CORS (adjust for your frontend domain)
    add_header 'Access-Control-Allow-Origin' 'https://sellr.com' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Meili-API-Key' always;

    location / {
        proxy_pass http://meilisearch;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Rate limiting (optional)
    limit_req_zone $binary_remote_addr zone=meili_limit:10m rate=10r/s;
    limit_req zone=meili_limit burst=20 nodelay;
}
```

### Step 3: Firewall Configuration

```bash
# UFW (Ubuntu)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw deny 7700/tcp  # Block direct access to MeiliSearch port
sudo ufw enable
```

---

## 🔑 API Key Management

### Create Search-Only Key (for Frontend)

```powershell
# Replace YOUR_MASTER_KEY with actual key
curl -X POST "http://localhost:7700/keys" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '{
    "description": "Sellr Frontend Search Key",
    "actions": ["search"],
    "indexes": ["products"],
    "expiresAt": null
  }'
```

### Create Admin Key (for Backend/NestJS)

```powershell
curl -X POST "http://localhost:7700/keys" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '{
    "description": "Sellr Backend Admin Key",
    "actions": ["*"],
    "indexes": ["*"],
    "expiresAt": null
  }'
```

### List All Keys

```powershell
curl -X GET "http://localhost:7700/keys" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"
```

---

## 📊 Index Configuration

### Create Products Index

```powershell
curl -X POST "http://localhost:7700/indexes" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '{
    "uid": "products",
    "primaryKey": "id"
  }'
```

### Configure Searchable Attributes

```powershell
curl -X PATCH "http://localhost:7700/indexes/products/settings/searchable-attributes" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '[
    "title",
    "description",
    "tags",
    "category",
    "condition"
  ]'
```

### Configure Filterable Attributes

```powershell
curl -X PATCH "http://localhost:7700/indexes/products/settings/filterable-attributes" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '[
    "category",
    "condition",
    "originalPrice",
    "discountedPrice",
    "discount",
    "userId"
  ]'
```

### Configure Sortable Attributes

```powershell
curl -X PATCH "http://localhost:7700/indexes/products/settings/sortable-attributes" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '[
    "originalPrice",
    "discountedPrice",
    "createdAt",
    "stock"
  ]'
```

### Configure Ranking Rules

```powershell
curl -X PATCH "http://localhost:7700/indexes/products/settings/ranking-rules" `
  -H "Content-Type: application/json" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY" `
  -d '[
    "words",
    "typo",
    "proximity",
    "attribute",
    "sort",
    "exactness",
    "originalPrice:asc"
  ]'
```

---

## 💾 Backup & Recovery

### Manual Backup (Docker Volume)

```bash
# Stop MeiliSearch
docker compose down

# Backup data directory
tar -czf meili_backup_$(date +%Y%m%d_%H%M%S).tar.gz ./data

# Restart MeiliSearch
docker compose up -d
```

### Create Dump (No Downtime)

```powershell
# Create dump
curl -X POST "http://localhost:7700/dumps" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"

# Response contains taskUid - check status
curl -X GET "http://localhost:7700/tasks/TASK_UID" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"

# Download dump file from ./data/dumps/
```

### Restore from Dump

```bash
# 1. Stop MeiliSearch
docker compose down

# 2. Clear existing data
rm -rf ./data/*

# 3. Place dump file in ./data/dumps/
# 4. Start MeiliSearch with import flag
docker compose run --rm meilisearch meilisearch --import-dump /meili_data/dumps/YOUR_DUMP_FILE.dump

# 5. Start normally
docker compose up -d
```

### Automated Backup Script

**backup.sh**:

```bash
#!/bin/bash

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
MEILI_KEY="YOUR_MASTER_KEY"

# Create backup directory
mkdir -p $BACKUP_DIR

# Create dump via API
echo "Creating MeiliSearch dump..."
TASK=$(curl -s -X POST "http://localhost:7700/dumps" \
  -H "X-Meili-API-Key: $MEILI_KEY" | jq -r '.taskUid')

echo "Task UID: $TASK"

# Wait for dump to complete (poll every 5 seconds)
while true; do
    STATUS=$(curl -s -X GET "http://localhost:7700/tasks/$TASK" \
      -H "X-Meili-API-Key: $MEILI_KEY" | jq -r '.status')

    if [ "$STATUS" == "succeeded" ]; then
        echo "Dump created successfully!"
        break
    elif [ "$STATUS" == "failed" ]; then
        echo "Dump failed!"
        exit 1
    fi

    echo "Waiting for dump... (status: $STATUS)"
    sleep 5
done

# Copy dump to backup directory
cp ./data/dumps/*.dump "$BACKUP_DIR/meili_dump_$DATE.dump"

# Compress backup
gzip "$BACKUP_DIR/meili_dump_$DATE.dump"

# Keep only last 7 days of backups
find $BACKUP_DIR -name "meili_dump_*.dump.gz" -mtime +7 -delete

echo "Backup completed: meili_dump_$DATE.dump.gz"
```

### Cron Job (Daily Backup at 2 AM)

```bash
# Edit crontab
crontab -e

# Add this line
0 2 * * * /path/to/meilisearch/backup.sh >> /path/to/meilisearch/backup.log 2>&1
```

---

## 📈 Monitoring

### Health Check

```powershell
curl http://localhost:7700/health
```

### Get Stats

```powershell
curl -X GET "http://localhost:7700/indexes/products/stats" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"
```

### View Logs

```bash
# Real-time logs
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100

# Specific service
docker logs sellr_meilisearch
```

### Resource Usage

```bash
docker stats sellr_meilisearch
```

---

## 🔧 Troubleshooting

### Issue: Container Won't Start

**Check logs**:

```bash
docker compose logs meilisearch
```

**Common causes**:

- Invalid MEILI_MASTER_KEY (must be at least 16 bytes)
- Port 7700 already in use
- Permission issues with ./data directory

**Fix permissions**:

```bash
sudo chown -R $(whoami) ./data
chmod -R 755 ./data
```

### Issue: Cannot Connect from NestJS

**Verify network**:

```bash
docker network inspect sellr_network
```

**Solution**: Ensure both containers are on same network, use service name `http://meilisearch:7700`

### Issue: Search Returns Empty Results

**Check if documents exist**:

```powershell
curl -X GET "http://localhost:7700/indexes/products/documents" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"
```

**Check indexing tasks**:

```powershell
curl -X GET "http://localhost:7700/tasks" `
  -H "X-Meili-API-Key: YOUR_MASTER_KEY"
```

### Issue: CORS Errors

**Solution 1**: Add CORS headers in Nginx (see Production Deployment)

**Solution 2**: Proxy through NestJS backend instead of direct browser calls

### Issue: Out of Memory

**Increase Docker memory limit** in Docker Desktop settings or docker-compose.yml:

```yaml
services:
  meilisearch:
    deploy:
      resources:
        limits:
          memory: 2G
```

---

## 📚 Additional Resources

- [MeiliSearch Documentation](https://docs.meilisearch.com/)
- [API Reference](https://docs.meilisearch.com/reference/api/overview.html)
- [Cloud Deployment Guide](https://docs.meilisearch.com/learn/cookbooks/docker.html)

---

## 🚨 Security Checklist

- [ ] Changed default MEILI_MASTER_KEY
- [ ] Created search-only API keys for frontend
- [ ] Enabled HTTPS/TLS with valid certificate
- [ ] Configured firewall to block direct access to port 7700
- [ ] Set up CORS restrictions
- [ ] Implemented rate limiting
- [ ] Configured automated backups
- [ ] Set up monitoring and alerting
- [ ] Restricted network access (Docker networks)
- [ ] Reviewed and minimized exposed ports
- [ ] Documented all API keys securely (not in git)

---

**Last Updated**: October 23, 2025
**MeiliSearch Version**: v1.11
#   M e l i S e a r c h L  
 