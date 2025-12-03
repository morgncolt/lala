@echo off
echo ========================================
echo Setting up port forwarding for LandLedger API
echo ========================================
echo.
echo This script will:
echo 1. Forward Windows port 4000 to WSL port 4000
echo 2. Add firewall rule to allow port 4000
echo.
echo NOTE: This requires Administrator privileges
echo.
pause

REM Check for administrator rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script must be run as Administrator!
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo.
echo [1/3] Getting WSL IP address...
for /f %%i in ('wsl -d Ubuntu-20.04 hostname -I') do set WSL_IP=%%i
echo WSL IP: %WSL_IP%

echo.
echo [2/3] Setting up port proxy (Windows port 4000 -> WSL port 4000)...
netsh interface portproxy delete v4tov4 listenport=4000 listenaddress=0.0.0.0
netsh interface portproxy add v4tov4 listenport=4000 listenaddress=0.0.0.0 connectport=4000 connectaddress=%WSL_IP%

echo.
echo [3/3] Adding firewall rule for port 4000...
netsh advfirewall firewall delete rule name="LandLedger API Port 4000"
netsh advfirewall firewall add rule name="LandLedger API Port 4000" dir=in action=allow protocol=TCP localport=4000

echo.
echo ========================================
echo Port forwarding setup complete!
echo ========================================
echo.
echo Your Android device can now access the API at:
echo http://192.168.0.23:4000
echo.
echo To verify the setup, run:
echo   netsh interface portproxy show all
echo.
pause
