# PowerShell Backup Script for MeiliSearch
# Windows-compatible version

param(
    [string]$MeiliHost = "http://localhost:7700",
    [string]$BackupDir = ".\backups",
    [int]$RetentionDays = 7
)

$ErrorActionPreference = "Stop"

# Get Master Key from environment or .env file
$MeiliKey = $env:MEILI_MASTER_KEY
if (-not $MeiliKey) {
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $keyLine = $envContent | Where-Object { $_ -match "MEILI_MASTER_KEY=(.+)" }
        if ($keyLine) {
            $MeiliKey = $Matches[1]
        }
    }
}

if (-not $MeiliKey) {
    Write-Host "Error: MEILI_MASTER_KEY not found" -ForegroundColor Red
    exit 1
}

# Create backup directory
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

$Date = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Starting MeiliSearch backup..." -ForegroundColor Green

# Create dump via API
Write-Host "Creating dump..."
$headers = @{
    "Content-Type" = "application/json"
    "X-Meili-API-Key" = $MeiliKey
}

try {
    $response = Invoke-RestMethod -Uri "$MeiliHost/dumps" -Method POST -Headers $headers
    $taskUid = $response.taskUid
    Write-Host "Task created with UID: $taskUid" -ForegroundColor Green
} catch {
    Write-Host "Failed to create dump: $_" -ForegroundColor Red
    exit 1
}

# Poll for completion
$maxWait = 300  # 5 minutes
$elapsed = 0

while ($elapsed -lt $maxWait) {
    try {
        $statusResponse = Invoke-RestMethod -Uri "$MeiliHost/tasks/$taskUid" -Method GET -Headers $headers
        $status = $statusResponse.status
        
        switch ($status) {
            "succeeded" {
                Write-Host "Dump created successfully!" -ForegroundColor Green
                break
            }
            "failed" {
                Write-Host "Dump creation failed!" -ForegroundColor Red
                Write-Host ($statusResponse.error | ConvertTo-Json)
                exit 1
            }
            { $_ -in @("enqueued", "processing") } {
                Write-Host "Status: $status... waiting" -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                $elapsed += 5
                continue
            }
            default {
                Write-Host "Unknown status: $status" -ForegroundColor Red
                exit 1
            }
        }
        
        if ($status -eq "succeeded") {
            break
        }
    } catch {
        Write-Host "Error checking task status: $_" -ForegroundColor Red
        exit 1
    }
}

if ($elapsed -ge $maxWait) {
    Write-Host "Timeout waiting for dump to complete" -ForegroundColor Red
    exit 1
}

# Find the most recent dump file
$dumpFiles = Get-ChildItem -Path ".\data\dumps\*.dump" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($dumpFiles.Count -eq 0) {
    Write-Host "No dump file found in .\data\dumps\" -ForegroundColor Red
    exit 1
}

$dumpFile = $dumpFiles[0].FullName
$backupFile = Join-Path $BackupDir "meili_dump_$Date.dump"

Write-Host "Copying dump to $backupFile..."
Copy-Item -Path $dumpFile -Destination $backupFile

Write-Host "Compressing backup..."
Compress-Archive -Path $backupFile -DestinationPath "$backupFile.zip" -Force
Remove-Item -Path $backupFile

$backupSize = (Get-Item "$backupFile.zip").Length / 1MB
Write-Host "Backup completed: $backupFile.zip ($([math]::Round($backupSize, 2)) MB)" -ForegroundColor Green

# Clean up old backups
Write-Host "Removing backups older than $RetentionDays days..."
$cutoffDate = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -Path $BackupDir -Filter "meili_dump_*.zip" | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force

Write-Host "Backup process complete!" -ForegroundColor Green
