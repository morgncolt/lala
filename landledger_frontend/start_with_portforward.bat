@echo off
echo ========================================
echo LandLedger Complete Launcher
echo ========================================

REM Check for administrator rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo This script requires Administrator privileges for port forwarding.
    echo Attempting to restart with admin rights...
    echo.
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo [1/4] Getting WSL IP address...
for /f %%i in ('wsl -d Ubuntu-20.04 hostname -I') do set WSL_IP=%%i
echo WSL IP: %WSL_IP%

echo.
echo [2/4] Setting up port forwarding...
netsh interface portproxy delete v4tov4 listenport=4000 listenaddress=0.0.0.0 >nul 2>&1
netsh interface portproxy add v4tov4 listenport=4000 listenaddress=0.0.0.0 connectport=4000 connectaddress=%WSL_IP%
netsh advfirewall firewall delete rule name="LandLedger API Port 4000" >nul 2>&1
netsh advfirewall firewall add rule name="LandLedger API Port 4000" dir=in action=allow protocol=TCP localport=4000 >nul
echo Port forwarding configured!

echo.
echo [3/4] Starting LandLedger API in WSL...
start "LandLedger API" wsl -d Ubuntu-20.04 bash -c "cd /home/morgan/landledger && ./safe_api_start.sh"
echo Waiting 5 seconds for API to start...
ping 127.0.0.1 -n 6 > nul

echo.
echo [4/5] Setting up ADB reverse port forwarding...
"%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe" reverse tcp:4000 tcp:4000 >nul 2>&1
echo ADB port forwarding configured!

echo.
echo [5/5] Launching Flutter on Android...
cd /d "%~dp0"
flutter run -d R5CYA0A3JQF

echo.
echo ========================================
echo Session ended
echo ========================================
pause
