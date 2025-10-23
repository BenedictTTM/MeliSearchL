# PowerShell Setup Script for MeiliSearch (Windows)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host "   MeiliSearch Setup for Sellr         " -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

# Check Docker
try {
    docker --version | Out-Null
} catch {
    Write-Host "Error: Docker is not installed" -ForegroundColor Red
    Write-Host "Please install Docker Desktop: https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}

try {
    docker compose version | Out-Null
} catch {
    Write-Host "Error: Docker Compose is not available" -ForegroundColor Red
    exit 1
}

# Create .env if it doesn't exist
if (-not (Test-Path ".env")) {
    Write-Host "Creating .env file..." -ForegroundColor Yellow
    
    # Generate random master key
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $masterKey = [Convert]::ToBase64String($bytes)
    
    $envContent = "# MeiliSearch Configuration`nMEILI_MASTER_KEY=$masterKey`nMEILI_ENV=development"
    $envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
    
    Write-Host "[OK] Created .env with generated master key" -ForegroundColor Green
} else {
    Write-Host "[OK] .env file already exists" -ForegroundColor Green
}

# Create data directory
if (-not (Test-Path "data")) {
    New-Item -ItemType Directory -Path "data" | Out-Null
    Write-Host "[OK] Created data directory" -ForegroundColor Green
}

# Start MeiliSearch
Write-Host ""
Write-Host "Starting MeiliSearch..." -ForegroundColor Blue
docker compose up -d

Write-Host "Waiting for MeiliSearch to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Wait for health check
$maxAttempts = 30
$attempt = 0

while ($attempt -lt $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:7700/health" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.Content -match "available") {
            Write-Host "[OK] MeiliSearch is healthy!" -ForegroundColor Green
            break
        }
    } catch {
        # Continue waiting
    }
    
    $attempt++
    Write-Host "Attempt $attempt/$maxAttempts..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
}

if ($attempt -eq $maxAttempts) {
    Write-Host "Error: MeiliSearch failed to start" -ForegroundColor Red
    docker compose logs
    exit 1
}

# Load master key from .env
$envContent = Get-Content ".env"
$masterKeyLine = $envContent | Where-Object { $_ -match "MEILI_MASTER_KEY=(.+)" }
$masterKey = $Matches[1]

$headers = @{
    "Content-Type" = "application/json"
    "X-Meili-API-Key" = $masterKey
}

Write-Host ""
Write-Host "Configuring MeiliSearch..." -ForegroundColor Blue

# Create products index
Write-Host "Creating products index..." -ForegroundColor Yellow
try {
    $body = '{"uid":"products","primaryKey":"id"}'
    Invoke-RestMethod -Uri "http://localhost:7700/indexes" -Method POST -Headers $headers -Body $body -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] Products index created" -ForegroundColor Green
    Start-Sleep -Seconds 2  # Wait for index to be ready
} catch {
    Write-Host "[OK] Products index exists" -ForegroundColor Green
}

# Configure searchable attributes
Write-Host "Configuring searchable attributes..." -ForegroundColor Yellow
$body = '["title","description","tags","category","condition"]'
try {
    Invoke-RestMethod -Uri "http://localhost:7700/indexes/products/settings/searchable-attributes" -Method PUT -Headers $headers -Body $body | Out-Null
    Write-Host "[OK] Searchable attributes configured" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not configure searchable attributes" -ForegroundColor Yellow
}

# Configure filterable attributes
Write-Host "Configuring filterable attributes..." -ForegroundColor Yellow
$body = '["category","condition","originalPrice","discountedPrice","discount","userId","stock"]'
try {
    Invoke-RestMethod -Uri "http://localhost:7700/indexes/products/settings/filterable-attributes" -Method PUT -Headers $headers -Body $body | Out-Null
    Write-Host "[OK] Filterable attributes configured" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not configure filterable attributes" -ForegroundColor Yellow
}

# Configure sortable attributes
Write-Host "Configuring sortable attributes..." -ForegroundColor Yellow
$body = '["originalPrice","discountedPrice","createdAt","stock","discount"]'
try {
    Invoke-RestMethod -Uri "http://localhost:7700/indexes/products/settings/sortable-attributes" -Method PUT -Headers $headers -Body $body | Out-Null
    Write-Host "[OK] Sortable attributes configured" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not configure sortable attributes" -ForegroundColor Yellow
}

# Create search-only API key
Write-Host ""
Write-Host "Creating API keys..." -ForegroundColor Blue
$body = @{
    description = "Sellr Frontend Search Key"
    actions = @("search")
    indexes = @("products")
    expiresAt = $null
} | ConvertTo-Json

$searchKeyResponse = Invoke-RestMethod -Uri "http://localhost:7700/keys" -Method POST -Headers $headers -Body $body
$searchKey = $searchKeyResponse.key
Write-Host "[OK] Search key created" -ForegroundColor Green

# Create admin key for backend
$body = @{
    description = "Sellr Backend Admin Key"
    actions = @("*")
    indexes = @("*")
    expiresAt = $null
} | ConvertTo-Json

$adminKeyResponse = Invoke-RestMethod -Uri "http://localhost:7700/keys" -Method POST -Headers $headers -Body $body
$adminKey = $adminKeyResponse.key
Write-Host "[OK] Admin key created" -ForegroundColor Green

# Save keys to file
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$keysContent = @"
# MeiliSearch API Keys for Sellr
# Generated on $date
# KEEP THESE KEYS SECURE - DO NOT COMMIT TO GIT

Master Key (Never expose to client):
$masterKey

Search-Only Key (Use in frontend):
$searchKey

Admin Key (Use in NestJS backend):
$adminKey

---
Add to your .env files:

Frontend (.env.local):
NEXT_PUBLIC_MEILI_HOST=http://localhost:7700
NEXT_PUBLIC_MEILI_SEARCH_KEY=$searchKey

Backend (.env):
MEILI_HOST=http://localhost:7700
MEILI_ADMIN_KEY=$adminKey
"@

$keysContent | Out-File -FilePath "api-keys.txt" -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   Setup Complete!                     " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "API Keys saved to: api-keys.txt" -ForegroundColor Cyan
Write-Host "WARNING: Keep api-keys.txt secure!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Add the API keys to your frontend and backend .env files"
Write-Host "2. Follow INTEGRATION_GUIDE.md to connect with NestJS"
Write-Host "3. Implement search functionality in your frontend"
Write-Host ""
Write-Host "MeiliSearch is running at: http://localhost:7700" -ForegroundColor Green
Write-Host ""
