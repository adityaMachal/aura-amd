@echo off
echo [Aura-AMD] Checking hardware monitoring tools...

nvidia-smi >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    echo [OK] nvidia-smi is already in your PATH.
    goto :end
)

IF EXIST "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" (
    echo [FIX] Adding NVIDIA NVSMI to your User PATH...
    setx PATH "%PATH%;C:\Program Files\NVIDIA Corporation\NVSMI"
    echo [SUCCESS] Please restart your terminal or VS Code for changes to take effect.
) ELSE (
    echo [WARN] Dedicated GPU tools not found. The app will fallback to DirectML generic metrics.
)

:end
pause
