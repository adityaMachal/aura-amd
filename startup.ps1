# Aura-AMD Parallel Startup & Model Sync Script
$ErrorActionPreference = "Stop"

# Configuration
$HF_REPO = "https://huggingface.co/breadOnLaptop/aura-amd-int8/resolve/main"
$ROOT = Get-Location
$ML_MODEL_DIR = Join-Path $ROOT "ml-engine\model\onnx"
$BACKEND_DIR = Join-Path $ROOT "backend"
$FRONTEND_DIR = Join-Path $ROOT "frontend"

# --- 1. Model Sync (Hugging Face Download) ---
if (!(Test-Path $ML_MODEL_DIR)) { New-Item -Path $ML_MODEL_DIR -ItemType Directory -Force }

$models = @("model-int8.onnx", "model-int8.onnx.data")

foreach ($file in $models) {
    $targetPath = Join-Path $ML_MODEL_DIR $file
    if (!(Test-Path $targetPath)) {
        Write-Host "📥 Downloading $file from Hugging Face..." -ForegroundColor Cyan
        $url = "$HF_REPO/$file"
        # Using Invoke-WebRequest for large file stream
        Invoke-WebRequest -Uri $url -OutFile $targetPath
        Write-Host "✅ $file downloaded." -ForegroundColor Green
    } else {
        Write-Host "✔️ $file already exists, skipping download." -ForegroundColor Gray
    }
}

Write-Host "`n🚀 Starting Aura-AMD Integrated Stack..." -ForegroundColor Cyan

# --- Garbage Collection (Cleanup) ---
function Cleanup {
    Write-Host "`n🧹 Garbage Collection: Killing parallel processes..." -ForegroundColor Yellow
    Get-Job | Stop-Job | Remove-Job

    $ports = @(8080, 3000)
    foreach ($port in $ports) {
        $proc = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($proc) { Stop-Process -Id $proc.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "System clean. Exit successful." -ForegroundColor Green
    Exit
}

trap { Cleanup }

# --- Launch Parallel Jobs ---
# Backend (Go)
Start-Job -Name "Aura-Backend" -ScriptBlock { param($p); cd $p; go run main.go } -ArgumentList $BACKEND_DIR

# Frontend (Next.js)
Start-Job -Name "Aura-Frontend" -ScriptBlock { param($p); cd $p; npm run dev } -ArgumentList $FRONTEND_DIR

# ML Environment Setup
Start-Job -Name "Aura-ML" -ScriptBlock { param($p); cd $p; .\.venv\Scripts\Activate.ps1 } -ArgumentList (Join-Path $ROOT "ml-engine")

Write-Host "Dashboard: http://localhost:3000" -ForegroundColor Green
Write-Host "ML Status: Active (INT8 Quantization)" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop all services and run garbage collection." -ForegroundColor Gray

while ($true) { Start-Sleep -Seconds 1 }
