#!/bin/bash

# MeiliSearch Setup Script
# Automates initial setup and configuration

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MeiliSearch Setup for Sellr         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

# Create .env if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    
    # Generate random master key
    MASTER_KEY=$(openssl rand -base64 32 | tr -d '\n')
    
    cat > .env << EOF
# MeiliSearch Configuration
MEILI_MASTER_KEY=$MASTER_KEY
MEILI_ENV=development
EOF
    
    echo -e "${GREEN}✓ Created .env with generated master key${NC}"
else
    echo -e "${GREEN}✓ .env file already exists${NC}"
fi

# Create data directory
if [ ! -d data ]; then
    mkdir -p data
    echo -e "${GREEN}✓ Created data directory${NC}"
fi

# Start MeiliSearch
echo -e "${BLUE}Starting MeiliSearch...${NC}"
docker compose up -d

echo -e "${YELLOW}Waiting for MeiliSearch to be ready...${NC}"
sleep 5

# Wait for health check
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:7700/health | grep -q "available"; then
        echo -e "${GREEN}✓ MeiliSearch is healthy!${NC}"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo -e "${YELLOW}Attempt $ATTEMPT/$MAX_ATTEMPTS...${NC}"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}Error: MeiliSearch failed to start${NC}"
    docker compose logs
    exit 1
fi

# Load master key
source .env

# Create products index
echo -e "${BLUE}Creating products index...${NC}"
curl -s -X POST "http://localhost:7700/indexes" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '{"uid":"products","primaryKey":"id"}' > /dev/null

echo -e "${GREEN}✓ Products index created${NC}"

# Configure searchable attributes
echo -e "${BLUE}Configuring searchable attributes...${NC}"
curl -s -X PATCH "http://localhost:7700/indexes/products/settings/searchable-attributes" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '["title","description","tags","category","condition"]' > /dev/null

echo -e "${GREEN}✓ Searchable attributes configured${NC}"

# Configure filterable attributes
echo -e "${BLUE}Configuring filterable attributes...${NC}"
curl -s -X PATCH "http://localhost:7700/indexes/products/settings/filterable-attributes" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '["category","condition","originalPrice","discountedPrice","discount","userId","stock"]' > /dev/null

echo -e "${GREEN}✓ Filterable attributes configured${NC}"

# Configure sortable attributes
echo -e "${BLUE}Configuring sortable attributes...${NC}"
curl -s -X PATCH "http://localhost:7700/indexes/products/settings/sortable-attributes" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '["originalPrice","discountedPrice","createdAt","stock","discount"]' > /dev/null

echo -e "${GREEN}✓ Sortable attributes configured${NC}"

# Create search-only API key
echo -e "${BLUE}Creating search-only API key for frontend...${NC}"
SEARCH_KEY_RESPONSE=$(curl -s -X POST "http://localhost:7700/keys" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '{
    "description": "Sellr Frontend Search Key",
    "actions": ["search"],
    "indexes": ["products"],
    "expiresAt": null
  }')

SEARCH_KEY=$(echo "$SEARCH_KEY_RESPONSE" | jq -r '.key')
echo -e "${GREEN}✓ Search key created${NC}"

# Create admin key for backend
echo -e "${BLUE}Creating admin API key for backend...${NC}"
ADMIN_KEY_RESPONSE=$(curl -s -X POST "http://localhost:7700/keys" \
  -H "Content-Type: application/json" \
  -H "X-Meili-API-Key: $MEILI_MASTER_KEY" \
  -d '{
    "description": "Sellr Backend Admin Key",
    "actions": ["*"],
    "indexes": ["*"],
    "expiresAt": null
  }')

ADMIN_KEY=$(echo "$ADMIN_KEY_RESPONSE" | jq -r '.key')
echo -e "${GREEN}✓ Admin key created${NC}"

# Save keys to file
cat > api-keys.txt << EOF
# MeiliSearch API Keys for Sellr
# Generated on $(date)
# KEEP THESE KEYS SECURE - DO NOT COMMIT TO GIT

Master Key (Never expose to client):
$MEILI_MASTER_KEY

Search-Only Key (Use in frontend):
$SEARCH_KEY

Admin Key (Use in NestJS backend):
$ADMIN_KEY

---
Add to your .env files:

Frontend (.env.local):
NEXT_PUBLIC_MEILI_HOST=http://localhost:7700
NEXT_PUBLIC_MEILI_SEARCH_KEY=$SEARCH_KEY

Backend (.env):
MEILI_HOST=http://localhost:7700
MEILI_ADMIN_KEY=$ADMIN_KEY
EOF

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Setup Complete! 🎉                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}API Keys saved to: ${NC}api-keys.txt"
echo -e "${YELLOW}⚠️  Keep api-keys.txt secure and DO NOT commit to git${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Add the API keys to your frontend and backend .env files"
echo "2. Update your NestJS product service to sync with MeiliSearch"
echo "3. Implement search functionality in your frontend"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  View logs:        docker compose logs -f"
echo "  Stop service:     docker compose down"
echo "  Restart service:  docker compose restart"
echo "  Run backup:       ./backup.sh"
echo ""
echo -e "${BLUE}MeiliSearch Dashboard:${NC}"
echo "  http://localhost:7700"
echo ""
