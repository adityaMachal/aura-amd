$ErrorActionPreference = "Stop"

# --- Paths ---
$ROOT           = Get-Location
$BACKEND_DIR    = Join-Path $ROOT "backend"
$FRONTEND_DIR   = Join-Path $ROOT "frontend"
$ML_DIR         = Join-Path $ROOT "ml-engine"
$VENV_ACTIVATE  = Join-Path $ML_DIR ".venv\Scripts\activate.bat"

# --- Globals & flags ---
$Global:BackendProc   = $null
$Global:FrontendProc  = $null
$script:CancelRequested = $false
$script:CleanupRunning  = $false

# --- Helpers ---
function Kill-ProcessTree {
    param([int]$ProcessId)

    if (-not $ProcessId) { return }

    try {
        Write-Host "RUN: taskkill /PID $ProcessId /T /F" -ForegroundColor Yellow
        & taskkill /PID $ProcessId /T /F 2>$null
    } catch {
        Write-Warning "taskkill failed for PID $ProcessId - falling back to Stop-Process."
        try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function TryGracefulClose {
    param([System.Diagnostics.Process]$Proc, [int]$timeoutSeconds = 5)

    if ($null -eq $Proc) { return $false }

    try {
        if ($Proc.HasExited) { return $true }

        Write-Host "RUN: Attempting graceful CloseMainWindow for PID $($Proc.Id)" -ForegroundColor DarkCyan

        $closed = $false
        try { $closed = $Proc.CloseMainWindow() } catch {}

        if ($closed) {
            $procExited = $Proc.WaitForExit($timeoutSeconds * 1000)
            if ($procExited) {
                Write-Host "SUCCESS: Process $($Proc.Id) exited gracefully." -ForegroundColor Green
                return $true
            }
        }
    } catch {
        # ignore and escalate
    }
    return $false
}

# --- Cleanup ---
function Cleanup {
    if ($script:CleanupRunning) { return }
    $script:CleanupRunning = $true

    Write-Host "`nRUN: Initiating Confirmed Hard-Kill..." -ForegroundColor Red

    if ($null -ne $Global:BackendProc) {
        Write-Host "WARN: Cleaning Backend (PID: $($Global:BackendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:BackendProc -timeoutSeconds 5)) {
            Kill-ProcessTree -ProcessId $Global:BackendProc.Id
        }
    } else {
        Write-Host "INFO: No backend process found." -ForegroundColor DarkGray
    }

    if ($null -ne $Global:FrontendProc) {
        Write-Host "WARN: Cleaning Frontend (PID: $($Global:FrontendProc.Id))" -ForegroundColor Yellow
        if (-not (TryGracefulClose -Proc $Global:FrontendProc -timeoutSeconds 5)) {
            Kill-ProcessTree -ProcessId $Global:FrontendProc.Id
        }
    } else {
        Write-Host "INFO: No frontend process found." -ForegroundColor DarkGray
    }

    Write-Host "RUN: Confirming port closure (8080/3000)..." -ForegroundColor DarkGray
    $ports = @(8080, 3000)
    foreach ($p in $ports) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue
            if ($conns) {
                foreach ($c in $conns) {
                    $owningPid = $c.OwningProcess
                    if ($owningPid) {
                        Write-Host "WARN: Force-closing process $owningPid on port $p" -ForegroundColor Red
                        Kill-ProcessTree -ProcessId $owningPid
                    }
                }
            }
        } catch {
            Write-Warning "Could not enumerate connections on port $p."
        }
    }

    Write-Host "--- Cleanup complete ---" -ForegroundColor Green
}

# --- Register Ctrl+C ---
$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
    $script:CancelRequested = $true
    Write-Host "`nWARN: Ctrl+C detected - shutting down..." -ForegroundColor Magenta
}

# --- Main run ---
try {
    $backendCmd  = "/k cd /d `"$BACKEND_DIR`" && `"$VENV_ACTIVATE`" && go run .\cmd\api\main.go"
    $frontendCmd = "/k cd /d `"$FRONTEND_DIR`" && npm run dev"

    $Global:BackendProc  = Start-Process -FilePath "cmd.exe" -ArgumentList $backendCmd -PassThru
    $Global:FrontendProc = Start-Process -FilePath "cmd.exe" -ArgumentList $frontendCmd -PassThru

    Write-Host "`nAura-AMD Active" -ForegroundColor Green
    Write-Host "Press Ctrl+C to trigger shutdown..." -ForegroundColor White

    while (-not $script:CancelRequested) {
        Start-Sleep -Seconds 1
    }
}
finally {
    Cleanup
}
