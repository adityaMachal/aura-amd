$ErrorActionPreference = "Stop"

# --- Paths ---
$ROOT           = Get-Location
$BACKEND_DIR    = Join-Path $ROOT "backend"
$FRONTEND_DIR   = Join-Path $ROOT "frontend"
$ML_DIR         = Join-Path $ROOT "ml-engine"
$ML_MODEL_DIR   = Join-Path $ML_DIR "model\onnx"
$VENV_PATH      = Join-Path $ML_DIR ".venv"
$VENV_ACTIVATE  = Join-Path $VENV_PATH "Scripts\activate.bat"

# --- Hugging Face Config ---
$HF_REPO = "https://huggingface.co/breadOnLaptop/aura-amd-int8/resolve/main"
$MODELS  = @("model-int8.onnx", "model-int8.onnx.data")

# --- Globals & flags ---
$Global:BackendProc   = $null
$Global:FrontendProc  = $null
$script:CancelRequested = $false
$script:CleanupRunning  = $false

# ==========================================
# PHASE 1: EXISTENCE CHECKS (SETUP)
# ==========================================
Write-Host "--- Phase 1: Environment & Model Verification ---" -ForegroundColor Cyan

# 1. Local Model Check
if (!(Test-Path $ML_MODEL_DIR)) { New-Item -ItemType Directory -Force -Path $ML_MODEL_DIR | Out-Null }
foreach ($file in $MODELS) {
    $target = Join-Path $ML_MODEL_DIR $file
    if (!(Test-Path $target)) {
        Write-Host "[Models] $file missing locally. Downloading from Hugging Face..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "$HF_REPO/$file" -OutFile $target
        Write-Host "[Models] $file successfully downloaded." -ForegroundColor Green
    } else { 
        Write-Host "[Models] $file verified locally." -ForegroundColor Gray 
    }
}

# 2. Frontend Dependency Check
if (!(Test-Path (Join-Path $FRONTEND_DIR "node_modules"))) {
    Write-Host "[Frontend] node_modules missing. Running npm install..." -ForegroundColor Yellow
    Push-Location $FRONTEND_DIR
    npm install
    Pop-Location
} else { Write-Host "[Frontend] node_modules verified." -ForegroundColor Gray }

# 3. ML-Engine Venv Check
if (!(Test-Path $VENV_PATH)) {
    Write-Host "[ML-Engine] .venv missing. Initializing Python environment..." -ForegroundColor Yellow
    Push-Location $ML_DIR
    python -m venv .venv
    .\.venv\Scripts\python.exe -m pip install --upgrade pip
    .\.venv\Scripts\pip.exe install -r requirements.txt
    Pop-Location
} else { Write-Host "[ML-Engine] Python .venv verified." -ForegroundColor Gray }

# ==========================================
# PHASE 2: HELPERS & CLEANUP LOGIC
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
        Write-Host "RUN: Attempting graceful CloseMainWindow for PID $($Proc.Id)" -ForegroundColor DarkCyan
        $closed = $Proc.CloseMainWindow()
        if ($closed) {
            if ($Proc.WaitForExit($timeoutSeconds * 1000)) { return $true }
        }
    } catch { }
    return $false
}

function Cleanup {
    if ($script:CleanupRunning) { return }
    $script:CleanupRunning = $true
    Write-Host "`nRUN: Initiating Confirmed Hard-Kill Garbage Collection..." -ForegroundColor Red

    if ($null -ne $Global:BackendProc) {
        Write-Host "WARN: Cleaning Backend (PID: $($Global:BackendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:BackendProc -timeoutSeconds 2)) {
            Kill-ProcessTree -ProcessId $Global:BackendProc.Id
        }
    }
    if ($null -ne $Global:FrontendProc) {
        Write-Host "WARN: Cleaning Frontend (PID: $($Global:FrontendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:FrontendProc -timeoutSeconds 2)) {
            Kill-ProcessTree -ProcessId $Global:FrontendProc.Id
        }
    }

    # Port Closure
    $ports = @(8080, 3000)
    foreach ($p in $ports) {
        $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
        if ($conns) {
            foreach ($c in $conns) {
                if ($c.OwningProcess) { Kill-ProcessTree -ProcessId $c.OwningProcess }
            }
        }
    }
    Write-Host "--- Cleanup complete. System Ready. ---" -ForegroundColor Green
    Exit
}

# --- Register Ctrl+C ---
$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
    $script:CancelRequested = $true
}

# ==========================================
# PHASE 3: MAIN EXECUTION
# ==========================================
try {
    Write-Host "`n--- Phase 2: Parallel Execution ---" -ForegroundColor Cyan
    
    # Logic: Start CMD -> CD Backend -> Activate ML Venv -> Go Run
    $backendCmd  = "/k cd /d `"$BACKEND_DIR`" && call `"$VENV_ACTIVATE`" && go run .\cmd\api\main.go"
    $frontendCmd = "/k cd /d `"$FRONTEND_DIR`" && npm run dev"

    $Global:BackendProc  = Start-Process -FilePath "cmd.exe" -ArgumentList $backendCmd -PassThru
    $Global:FrontendProc = Start-Process -FilePath "cmd.exe" -ArgumentList $frontendCmd -PassThru

    Write-Host "`nAura-AMD Active (INT8 Optimization)" -ForegroundColor Green
    Write-Host "Dashboard: http://localhost:3000" -ForegroundColor White
    Write-Host "Press Ctrl+C in THIS window to stop all services." -ForegroundColor Magenta

    while (-not $script:CancelRequested) { Start-Sleep -Seconds 1 }
}
finally {
    Cleanup
}