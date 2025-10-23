# 🚀 Quick Start - MeiliSearch for Sellr

## Windows Setup (5 Minutes)

### Step 1: Run Setup Script

Open PowerShell in the `meilisearch` folder:

```powershell
cd meilisearch
.\setup.ps1
```

This will:

- ✅ Generate secure master key
- ✅ Start MeiliSearch container
- ✅ Create products index
- ✅ Configure search settings
- ✅ Generate API keys
- ✅ Save keys to `api-keys.txt`

### Step 2: Add Keys to Your Projects

**Frontend** (`frontend/.env.local`):

```env
NEXT_PUBLIC_MEILI_HOST=http://localhost:7700
NEXT_PUBLIC_MEILI_SEARCH_KEY=your_search_key_from_api-keys.txt
```

**Backend** (`Backend/.env`):

```env
MEILI_HOST=http://localhost:7700
MEILI_ADMIN_KEY=your_admin_key_from_api-keys.txt
```

### Step 3: Verify Installation

```powershell
# Check health
curl http://localhost:7700/health

# View logs
docker compose logs -f
```

---

## Daily Operations

### Start MeiliSearch

```powershell
docker compose up -d
```

### Stop MeiliSearch

```powershell
docker compose down
```

### View Logs

```powershell
docker compose logs -f
```

### Backup Data

```powershell
.\backup.ps1
```

---

## Testing the Search

### Add a Test Product

```powershell
$headers = @{
    "Content-Type" = "application/json"
    "X-Meili-API-Key" = "YOUR_MASTER_KEY"
}

$body = @(
    @{
        id = 1
        title = "MacBook Pro 16"
        description = "Powerful laptop for developers"
        originalPrice = 2499.99
        discountedPrice = 2299.99
        discount = 8
        category = "electronics"
        condition = "new"
        tags = @("laptop", "apple", "macbook")
        stock = 5
    }
) | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:7700/indexes/products/documents" -Method POST -Headers $headers -Body $body
```

### Search for Products

```powershell
$searchBody = @{ q = "macbook" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:7700/indexes/products/search" -Method POST -Headers $headers -Body $searchBody
```

---

## Troubleshooting

### Container Won't Start

```powershell
# Check logs
docker compose logs

# Restart container
docker compose restart
```

### Port Already in Use

```powershell
# Find process using port 7700
netstat -ano | findstr :7700

# Kill process (replace PID with actual process ID)
taskkill /PID <PID> /F
```

### Reset Everything

```powershell
docker compose down
Remove-Item -Recurse -Force data
.\setup.ps1
```

---

## Production Deployment Checklist

- [ ] Change `MEILI_MASTER_KEY` to strong random value
- [ ] Set `MEILI_ENV=production`
- [ ] Set up reverse proxy (Nginx/Caddy) with HTTPS
- [ ] Configure firewall to block direct port 7700 access
- [ ] Use search-only keys in frontend (never expose master key)
- [ ] Set up automated backups (Task Scheduler)
- [ ] Configure monitoring and alerts
- [ ] Store backups in cloud storage (Azure Blob/AWS S3)

---

## Need Help?

- 📖 Full Documentation: See `README.md`
- 🔧 MeiliSearch Docs: https://docs.meilisearch.com/
- 💬 Issues: Create issue in project repo
