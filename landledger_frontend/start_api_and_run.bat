@echo off
echo ========================================
echo Starting LandLedger Backend API in WSL
echo ========================================

REM Start WSL and run the API script in the background
start "LandLedger API" wsl -d Ubuntu-20.04 bash -c "cd /home/morgan/landledger && ./safe_api_start.sh"

echo Waiting 5 seconds for API to start...
ping 127.0.0.1 -n 6 > nul

echo ========================================
echo Setting up ADB reverse port forwarding
echo ========================================
"%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe" reverse tcp:4000 tcp:4000
echo ADB port forwarding configured!

echo.
echo ========================================
echo Starting Flutter on Android Device
echo ========================================

REM Run Flutter on Android device
flutter run -d R5CYA0A3JQF

echo ========================================
echo Flutter app closed
echo ========================================
pause
