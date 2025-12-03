@echo off
REM LandLedger Backend API Startup Script for Windows

cd /d "%~dp0"

echo =========================================
echo   LandLedger Backend API Startup
echo =========================================
echo.

REM Check if node is installed
where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Node.js is not installed
    echo Please install Node.js from https://nodejs.org/
    pause
    exit /b 1
)

REM Check if node_modules exists
if not exist "node_modules\" (
    echo Installing dependencies...
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Failed to install dependencies
        pause
        exit /b 1
    )
)

REM Kill any existing process on port 4000
echo Checking for existing processes on port 4000...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":4000.*LISTENING"') do (
    echo Found existing process on port 4000 ^(PID: %%a^)
    echo Stopping existing process...
    taskkill /F /PID %%a >nul 2>&1
    timeout /t 1 /nobreak >nul
)

REM Get local IP address
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr "IPv4" ^| findstr "192.168"') do (
    for /f "tokens=1" %%b in ("%%a") do set LOCAL_IP=%%b
)

echo.
echo =========================================
echo Starting LandLedger Backend API...
echo =========================================
echo Local:   http://localhost:4000
echo Network: http://%LOCAL_IP%:4000
echo Android: http://192.168.0.23:4000
echo =========================================
echo.
echo Press Ctrl+C to stop the server
echo.

REM Start the server
node server.js
