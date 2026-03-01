# Force UTF-8 Encoding to fix the emoji/character corruption
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# --- Project Paths ---
$ROOT           = Get-Location
$BACKEND_DIR    = Join-Path $ROOT "backend"
$FRONTEND_DIR   = Join-Path $ROOT "frontend"
$ML_DIR         = Join-Path $ROOT "ml-engine"
$ML_MODEL_DIR   = Join-Path $ML_DIR "model\onnx"
$RUNTIMES_DIR   = Join-Path $ROOT ".runtimes"

$NODE_DIR = Join-Path $RUNTIMES_DIR "node"
$GO_DIR   = Join-Path $RUNTIMES_DIR "go\go"
$PY_DIR   = Join-Path $RUNTIMES_DIR "python\tools"

# --- Globals & flags ---
$Global:BackendProc     = $null
$Global:FrontendProc    = $null
$script:CancelRequested = $false
$script:CleanupRunning  = $false

# ==========================================
# PHASE 1: HELPERS & GARBAGE COLLECTION
# ==========================================
function Kill-ProcessTree {
    param([int]$ProcessId)
    if (-not $ProcessId) { return }
    try {
        Write-Host "RUN: taskkill /PID $ProcessId /T /F" -ForegroundColor Yellow
        & taskkill /PID $ProcessId /T /F 2>$null
    } catch {
        try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function TryGracefulClose {
    param([System.Diagnostics.Process]$Proc, [int]$timeoutSeconds = 5)
    if ($null -eq $Proc) { return $false }
    try {
        if ($Proc.HasExited) { return $true }
        $closed = $false
        try { $closed = $Proc.CloseMainWindow() } catch {}
        if ($closed) {
            if ($Proc.WaitForExit($timeoutSeconds * 1000)) { return $true }
        }
    } catch { }
    return $false
}

function Cleanup {
    if ($script:CleanupRunning) { return }
    $script:CleanupRunning = $true
    Write-Host "`nRUN: Initiating Confirmed Hard-Kill..." -ForegroundColor Red

    if ($null -ne $Global:BackendProc) {
        Write-Host "WARN: Cleaning Backend (PID: $($Global:BackendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:BackendProc -timeoutSeconds 3)) { Kill-ProcessTree -ProcessId $Global:BackendProc.Id }
    }
    if ($null -ne $Global:FrontendProc) {
        Write-Host "WARN: Cleaning Frontend (PID: $($Global:FrontendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:FrontendProc -timeoutSeconds 3)) { Kill-ProcessTree -ProcessId $Global:FrontendProc.Id }
    }

    $ports = @(8080, 3000)
    foreach ($p in $ports) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
            if ($conns) {
                foreach ($c in $conns) {
                    if ($c.OwningProcess) { Kill-ProcessTree -ProcessId $c.OwningProcess }
                }
            }
        } catch { }
    }
    Write-Host "--- Cleanup complete ---" -ForegroundColor Green
    Exit
}

$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action { $script:CancelRequested = $true }

# ==========================================
# PHASE 2: DYNAMIC RUNTIME RESOLUTION
# ==========================================
Write-Host "--- Phase 1: Checking Local Environments ---" -ForegroundColor Cyan
$runtimePathAdditions = ""
if (!(Test-Path $RUNTIMES_DIR)) { New-Item -ItemType Directory -Force -Path $RUNTIMES_DIR | Out-Null }

# 1. Node Check
if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "WARN: Node.js not found. Provisioning portable version..." -ForegroundColor Yellow
    if (!(Test-Path $NODE_DIR)) {
        $nodeZip = Join-Path $RUNTIMES_DIR "node.zip"
        Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.11.1/node-v20.11.1-win-x64.zip" -OutFile $nodeZip
        Expand-Archive -Path $nodeZip -DestinationPath $RUNTIMES_DIR -Force
        Rename-Item -Path (Join-Path $RUNTIMES_DIR "node-v20.11.1-win-x64") -NewName "node"
        Remove-Item $nodeZip
    }
    $runtimePathAdditions += "$NODE_DIR;"
}

# 2. Go Check
if ($null -eq (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Host "WARN: Go not found. Provisioning portable version..." -ForegroundColor Yellow
    if (!(Test-Path $GO_DIR)) {
        $goZip = Join-Path $RUNTIMES_DIR "go.zip"
        Invoke-WebRequest -Uri "https://go.dev/dl/go1.22.1.windows-amd64.zip" -OutFile $goZip
        Expand-Archive -Path $goZip -DestinationPath $RUNTIMES_DIR -Force
        Remove-Item $goZip
    }
    $runtimePathAdditions += "$GO_DIR\bin;"
}

# 3. Python Check
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "WARN: Python not found. Provisioning portable version..." -ForegroundColor Yellow
    if (!(Test-Path $PY_DIR)) {
        $pyZip = Join-Path $RUNTIMES_DIR "python.zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/python/3.12.2" -OutFile $pyZip
        Expand-Archive -Path $pyZip -DestinationPath (Join-Path $RUNTIMES_DIR "python") -Force
        Remove-Item $pyZip
    }
    $runtimePathAdditions += "$PY_DIR;$PY_DIR\Scripts;"
}

if ($runtimePathAdditions -ne "") { $env:PATH = $runtimePathAdditions + $env:PATH }

# ==========================================
# PHASE 3: DEPENDENCY, VENV, & PRODUCTION BUILD
# ==========================================
Write-Host "`n--- Phase 2: Assets & Production Build ---" -ForegroundColor Cyan

# Model Sync
$HF_REPO = "https://huggingface.co/breadOnLaptop/aura-amd-int8/resolve/main"
$MODELS  = @("model-int8.onnx", "model-int8.onnx.data")
if (!(Test-Path $ML_MODEL_DIR)) { New-Item -ItemType Directory -Force -Path $ML_MODEL_DIR | Out-Null }
foreach ($file in $MODELS) {
    $target = Join-Path $ML_MODEL_DIR $file
    if (!(Test-Path $target)) {
        Write-Host "RUN: Downloading $file from Hugging Face..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "$HF_REPO/$file" -OutFile $target
    }
}

# ML .venv Setup
$VENV_DIR = Join-Path $ML_DIR ".venv"
if (!(Test-Path $VENV_DIR)) {
    Write-Host "RUN: Creating isolated .venv and installing ML dependencies..." -ForegroundColor Yellow
    Push-Location $ML_DIR
    python -m venv .venv
    .\.venv\Scripts\python.exe -m pip install --upgrade pip
    .\.venv\Scripts\python.exe -m pip install -r requirements.txt
    Pop-Location
}

# Compile Go Backend inside the backend/ folder
$backendExe = Join-Path $BACKEND_DIR "backend.exe"
if (!(Test-Path $backendExe)) {
    Write-Host "RUN: Compiling Go Backend to binary..." -ForegroundColor Yellow
    Push-Location $BACKEND_DIR; go build -o backend.exe .\cmd\api\main.go; Pop-Location
}

# Build Frontend to frontend/out/
if (!(Test-Path (Join-Path $FRONTEND_DIR "out"))) {
    Write-Host "RUN: Building Next.js Frontend for Production..." -ForegroundColor Yellow
    Push-Location $FRONTEND_DIR
    if (!(Test-Path "node_modules")) { npm install }
    npm run build
    Pop-Location
}

# ==========================================
# PHASE 4: EXECUTION (Low RAM Mode)
# ==========================================
try {
    Write-Host "`n--- Phase 3: Launching Services ---" -ForegroundColor Cyan

    # FIX: Run local Go exe and use 'npx serve' for the static frontend
    $backendCmd  = "/k cd /d `"$BACKEND_DIR`" & .\backend.exe"
    $frontendCmd = "/k cd /d `"$FRONTEND_DIR`" & npx serve@latest out -p 3000"

    $Global:BackendProc  = Start-Process -FilePath "cmd.exe" -ArgumentList $backendCmd -PassThru
    $Global:FrontendProc = Start-Process -FilePath "cmd.exe" -ArgumentList $frontendCmd -PassThru

    Write-Host "`n🚀 Aura-AMD Active (Production Mode - High Performance)" -ForegroundColor Green
    Write-Host "Dashboard: http://localhost:3000" -ForegroundColor White
    Write-Host "Press Ctrl+C in this window to trigger Hard-Kill shutdown..." -ForegroundColor Magenta

    while (-not $script:CancelRequested) { Start-Sleep -Seconds 1 }
} finally {
    Cleanup
}
