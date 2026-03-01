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

$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -SourceIdentifier "CtrlC_Pressed" -Action {
    New-Event -SourceIdentifier "Shutdown_Triggered" | Out-Null
}

# ==========================================
# PHASE 2: DYNAMIC RUNTIME & VERSION RESOLUTION
# ==========================================
Write-Host "--- Phase 1: Checking Local Environments & Versions ---" -ForegroundColor Cyan
$runtimePathAdditions = ""
if (!(Test-Path $RUNTIMES_DIR)) { New-Item -ItemType Directory -Force -Path $RUNTIMES_DIR | Out-Null }

$MIN_NODE = [version]"20.11.1"
$MIN_GO   = [version]"1.22.1"
$MIN_PY   = [version]"3.12.10"

# 1. Node.js Check
$needNode = $true
if (Get-Command node -ErrorAction SilentlyContinue) {
    try {
        $nodeVerStr = (node -v).Trim().TrimStart('v')
        if ([version]$nodeVerStr -ge $MIN_NODE) {
            $needNode = $false
            Write-Host "INFO: Local Node.js ($nodeVerStr) meets minimum ($MIN_NODE)." -ForegroundColor DarkGray
        } else { Write-Host "WARN: Local Node.js ($nodeVerStr) is outdated. Minimum is $MIN_NODE." -ForegroundColor Yellow }
    } catch { }
}
if ($needNode) {
    Write-Host "RUN: Provisioning portable Node.js..." -ForegroundColor Yellow
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
$needGo = $true
if (Get-Command go -ErrorAction SilentlyContinue) {
    try {
        $goOut = go version
        if ($goOut -match 'go(\d+\.\d+(\.\d+)?)') {
            $goVerStr = $matches[1]
            if ($goVerStr.Split('.').Count -eq 2) { $goVerStr += ".0" }
            if ([version]$goVerStr -ge $MIN_GO) {
                $needGo = $false
                Write-Host "INFO: Local Go ($goVerStr) meets minimum ($MIN_GO)." -ForegroundColor DarkGray
            } else { Write-Host "WARN: Local Go ($goVerStr) is outdated. Minimum is $MIN_GO." -ForegroundColor Yellow }
        }
    } catch { }
}
if ($needGo) {
    Write-Host "RUN: Provisioning portable Go runtime..." -ForegroundColor Yellow
    if (!(Test-Path $GO_DIR)) {
        $goZip = Join-Path $RUNTIMES_DIR "go.zip"
        Invoke-WebRequest -Uri "https://go.dev/dl/go1.22.1.windows-amd64.zip" -OutFile $goZip
        Expand-Archive -Path $goZip -DestinationPath $RUNTIMES_DIR -Force
        Remove-Item $goZip
    }
    $runtimePathAdditions += "$GO_DIR\bin;"
}

# 3. Python Check
$needPy = $true
if (Get-Command python -ErrorAction SilentlyContinue) {
    try {
        $pyOut = python -V 2>&1 | Out-String
        if ($pyOut -match 'Python (\d+\.\d+\.\d+)') {
            $pyVerStr = $matches[1]
            if ([version]$pyVerStr -ge $MIN_PY) {
                $needPy = $false
                Write-Host "INFO: Local Python ($pyVerStr) meets minimum ($MIN_PY)." -ForegroundColor DarkGray
            } else { Write-Host "WARN: Local Python ($pyVerStr) is outdated. Minimum is $MIN_PY." -ForegroundColor Yellow }
        }
    } catch { }
}
if ($needPy) {
    Write-Host "RUN: Provisioning portable Python $MIN_PY..." -ForegroundColor Yellow
    if (!(Test-Path $PY_DIR)) {
        $pyZip = Join-Path $RUNTIMES_DIR "python.zip"
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/python/$MIN_PY" -OutFile $pyZip
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

# Model Sync with Atomic Downloads and Size Verification
$HF_REPO = "https://huggingface.co/breadOnLaptop/aura-amd-int8/resolve/main"
$MODELS  = @("model-int8.onnx", "model-int8.onnx.data")
if (!(Test-Path $ML_MODEL_DIR)) { New-Item -ItemType Directory -Force -Path $ML_MODEL_DIR | Out-Null }

# Enforce stable network protocol for large downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($file in $MODELS) {
    $target = Join-Path $ML_MODEL_DIR $file
    $tmpTarget = "$target.tmp"
    $needsDownload = $false

    # Clean up any leftover temp files from a previous crashed run
    if (Test-Path $tmpTarget) { Remove-Item $tmpTarget -Force }

    # Integrity Check
    if (Test-Path $target) {
        $localSize = (Get-Item $target).Length
        # If the large .data file is less than 2.5 GB, it's a corrupted/partial file
        if ($file -match "onnx.data" -and $localSize -lt 2500000000) {
            Write-Host "WARN: $file is corrupted or incomplete (Local Size: $localSize bytes). Re-downloading..." -ForegroundColor Yellow
            Remove-Item $target -Force
            $needsDownload = $true
        } else {
            Write-Host "INFO: $file verified successfully." -ForegroundColor DarkGray
        }
    } else {
        $needsDownload = $true
    }

    if ($needsDownload) {
        Write-Host "RUN: Downloading $file from Hugging Face (This may take several minutes)..." -ForegroundColor Yellow
        try {
            # Download to a temporary file first
            Invoke-WebRequest -Uri "$HF_REPO/$file" -OutFile $tmpTarget
            # Only rename it to the official file if it completes 100% without errors
            Rename-Item -Path $tmpTarget -NewName $file -Force
        } catch {
            Write-Host "`nERROR: Download interrupted or failed. Please run the script again." -ForegroundColor Red
            if (Test-Path $tmpTarget) { Remove-Item $tmpTarget -Force }
            Exit
        }
    }
}

$VENV_DIR = Join-Path $ML_DIR ".venv"
$REQ_FLAG = Join-Path $ML_DIR ".installed"

if (!(Test-Path $VENV_DIR) -or !(Test-Path $REQ_FLAG)) {
    Write-Host "RUN: Creating/Repairing isolated .venv and installing ML dependencies..." -ForegroundColor Yellow
    Push-Location $ML_DIR

    if (Test-Path $VENV_DIR) { Remove-Item -Path $VENV_DIR -Recurse -Force }
    python -m venv .venv

    $VENV_PYTHON = Join-Path $VENV_DIR "Scripts\python.exe"
    if (!(Test-Path $VENV_PYTHON)) { $VENV_PYTHON = Join-Path $VENV_DIR "bin\python.exe" }

    if (Test-Path $VENV_PYTHON) {
        & $VENV_PYTHON -m pip install --upgrade pip
        & $VENV_PYTHON -m pip install -r requirements.txt
        New-Item -ItemType File -Path $REQ_FLAG -Force | Out-Null
    } else {
        Write-Host "ERROR: Python failed to create the virtual environment." -ForegroundColor Red
        Exit
    }
    Pop-Location
} else {
    Write-Host "INFO: Python .venv is healthy and verified." -ForegroundColor DarkGray
}

Write-Host "RUN: Compiling Go Backend to binary..." -ForegroundColor Yellow
Push-Location $BACKEND_DIR
go build -o backend.exe .\cmd\api\main.go
Pop-Location

Write-Host "RUN: Building Next.js Frontend for Production..." -ForegroundColor Yellow
Push-Location $FRONTEND_DIR
if (!(Test-Path "node_modules")) { npm install }
npm run build
Pop-Location

# ==========================================
# PHASE 4: EXECUTION (High Priority Mode)
# ==========================================
try {
    Write-Host "`n--- Phase 3: Launching Services ---" -ForegroundColor Cyan

    $backendCmd  = "/k cd /d `"$BACKEND_DIR`" & .\backend.exe"
    $frontendCmd = "/k cd /d `"$FRONTEND_DIR`" & npx serve@latest out -p 3000"

    $Global:BackendProc  = Start-Process -FilePath "cmd.exe" -ArgumentList $backendCmd -PassThru
    $Global:FrontendProc = Start-Process -FilePath "cmd.exe" -ArgumentList $frontendCmd -PassThru

    try {
        $Global:BackendProc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        $Global:FrontendProc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal
    } catch { }

    Write-Host "`n🚀 Aura-AMD Active (Production Mode - High Priority)" -ForegroundColor Green
    Write-Host "Dashboard: http://localhost:3000" -ForegroundColor White
    Write-Host "Press Ctrl+C in this window to trigger Hard-Kill shutdown..." -ForegroundColor Magenta

    Wait-Event -SourceIdentifier "Shutdown_Triggered" | Out-Null
} finally {
    Cleanup
}
