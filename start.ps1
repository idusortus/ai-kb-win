# start.ps1 — Launch all AI Knowledge Base services
# Usage: .\start.ps1
#   -SkipSupabase   Skip starting Supabase (if already running)
#   -SkipOllama     Skip Ollama check

param(
    [switch]$SkipSupabase,
    [switch]$SkipOllama
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot

Write-Host "`n=== AI Knowledge Base — Starting Services ===" -ForegroundColor Cyan

# ── 1. Check Ollama ──────────────────────────────────────────────────────────
if (-not $SkipOllama) {
    Write-Host "`n[1/4] Checking Ollama..." -ForegroundColor Yellow
    try {
        $ollamaVersion = & ollama --version 2>&1
        Write-Host "  Ollama found: $ollamaVersion" -ForegroundColor Green

        # Verify required models are pulled
        $models = & ollama list 2>&1 | Out-String
        $missing = @()
        if ($models -notmatch 'nomic-embed-text') { $missing += 'nomic-embed-text' }
        if ($models -notmatch 'llama3\.2:3b')      { $missing += 'llama3.2:3b' }

        if ($missing.Count -gt 0) {
            Write-Host "  Pulling missing models: $($missing -join ', ')..." -ForegroundColor Yellow
            foreach ($m in $missing) {
                & ollama pull $m
            }
        } else {
            Write-Host "  Required models present (nomic-embed-text, llama3.2:3b)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  WARNING: Ollama not found or not running. Install with: winget install Ollama.Ollama" -ForegroundColor Red
        Write-Host "  The API will fail without Ollama (unless OPENAI_API_KEY is set)." -ForegroundColor Red
    }
} else {
    Write-Host "`n[1/4] Ollama check skipped" -ForegroundColor DarkGray
}

# ── 2. Start Supabase ────────────────────────────────────────────────────────
if (-not $SkipSupabase) {
    Write-Host "`n[2/4] Starting Supabase..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    try {
        $status = & supabase status 2>&1 | Out-String
        if ($status -match 'API URL') {
            Write-Host "  Supabase already running" -ForegroundColor Green
        } else {
            & supabase start
            Write-Host "  Supabase started" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Starting Supabase (first run may take a few minutes)..." -ForegroundColor Yellow
        & supabase start
        Write-Host "  Supabase started" -ForegroundColor Green
    }
    Pop-Location
} else {
    Write-Host "`n[2/4] Supabase start skipped" -ForegroundColor DarkGray
}

# ── 3. Activate Python venv & start Ingest API ──────────────────────────────
Write-Host "`n[3/4] Starting Ingest API (FastAPI :8000)..." -ForegroundColor Yellow
$venvActivate = Join-Path $ProjectRoot '.venv\Scripts\Activate.ps1'
if (-not (Test-Path $venvActivate)) {
    Write-Host "  Python venv not found. Creating..." -ForegroundColor Yellow
    & py -m venv (Join-Path $ProjectRoot '.venv')
    & $venvActivate
    & pip install -r (Join-Path $ProjectRoot 'requirements.txt')
} 

$ingestJob = Start-Process -PassThru -NoNewWindow -FilePath 'powershell' -ArgumentList @(
    '-NoProfile', '-Command',
    "Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned; & '$venvActivate'; Set-Location '$ProjectRoot'; uvicorn ingest_api:app --port 8000 --reload"
)
Write-Host "  Ingest API started (PID: $($ingestJob.Id))" -ForegroundColor Green

# ── 4. Start .NET RagApi ─────────────────────────────────────────────────────
Write-Host "`n[4/4] Starting RagApi (.NET :5000)..." -ForegroundColor Yellow
$ragApiDir = Join-Path $ProjectRoot 'RagApi'

$ragJob = Start-Process -PassThru -NoNewWindow -FilePath 'dotnet' -ArgumentList @(
    'run', '--project', $ragApiDir
)
Write-Host "  RagApi started (PID: $($ragJob.Id))" -ForegroundColor Green

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n=== All services launched ===" -ForegroundColor Cyan
Write-Host @"

  Supabase Studio:  http://localhost:54323
  Ingest API:       http://localhost:8000/health
  RagApi + Chat UI: http://localhost:5000
  Health check:     http://localhost:5000/health

  To stop:  .\stop.ps1   (or close this terminal)

"@ -ForegroundColor White

# ── Wait for Ctrl+C, then clean up ──────────────────────────────────────────
Write-Host "Press Ctrl+C to stop all services..." -ForegroundColor DarkGray

try {
    # Keep script alive — wait for both child processes
    while (-not $ingestJob.HasExited -or -not $ragJob.HasExited) {
        Start-Sleep -Seconds 2
    }
} finally {
    Write-Host "`nShutting down..." -ForegroundColor Yellow
    if (-not $ingestJob.HasExited) { Stop-Process -Id $ingestJob.Id -Force -ErrorAction SilentlyContinue }
    if (-not $ragJob.HasExited)    { Stop-Process -Id $ragJob.Id -Force -ErrorAction SilentlyContinue }
    Write-Host "Services stopped." -ForegroundColor Green
}
