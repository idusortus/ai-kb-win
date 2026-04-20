# stop.ps1 — Stop AI Knowledge Base services
# Stops the Ingest API (uvicorn) and RagApi (dotnet) processes.
# Supabase is left running (use `supabase stop` to shut it down).

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "`n=== Stopping AI Knowledge Base services ===" -ForegroundColor Cyan

# Kill uvicorn (Ingest API)
$uvicorn = Get-Process -Name 'uvicorn' -ErrorAction SilentlyContinue
if (-not $uvicorn) {
    # uvicorn may appear as a python process
    $uvicorn = Get-Process -Name 'python', 'python3' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'uvicorn|ingest_api' }
}
if ($uvicorn) {
    $uvicorn | Stop-Process -Force
    Write-Host "  Ingest API stopped" -ForegroundColor Green
} else {
    Write-Host "  Ingest API not running" -ForegroundColor DarkGray
}

# Kill dotnet RagApi
$dotnet = Get-Process -Name 'dotnet', 'RagApi' -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'RagApi' }
if ($dotnet) {
    $dotnet | Stop-Process -Force
    Write-Host "  RagApi stopped" -ForegroundColor Green
} else {
    Write-Host "  RagApi not running" -ForegroundColor DarkGray
}

Write-Host "`nNote: Supabase is still running. Use 'supabase stop' to shut it down." -ForegroundColor Yellow
Write-Host ""
