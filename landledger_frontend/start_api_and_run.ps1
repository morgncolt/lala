# LandLedger API and Flutter Launcher
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting LandLedger Backend API in WSL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Start WSL and run the API script in a new window
Start-Process wsl -ArgumentList "-d Ubuntu-20.04 bash -c 'cd /home/morgan/landledger && ./safe_api_start.sh'" -WindowStyle Normal

Write-Host "Waiting 5 seconds for API to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setting up ADB reverse port forwarding" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" reverse tcp:4000 tcp:4000
Write-Host "ADB port forwarding configured!" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Starting Flutter on Android Device" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Run Flutter on Android device
flutter run -d R5CYA0A3JQF

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flutter app closed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Press any key to continue..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
