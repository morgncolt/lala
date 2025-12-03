# How to Run LandLedger Flutter App with Backend API

This guide explains how to automatically start your backend API in WSL before running the Flutter app on Android.

## ⚠️ IMPORTANT: First-Time Setup

Your Android device needs to reach the API running in WSL. This requires port forwarding.

### One-Time Setup (Run as Administrator):

**Option A: Automatic Setup (Recommended)**
1. Right-click `start_with_portforward.bat`
2. Select **"Run as administrator"**
3. This will set up port forwarding and launch everything

**Option B: Manual Setup**
1. Right-click `setup_port_forwarding.bat`
2. Select **"Run as administrator"**
3. Follow the prompts

This configures Windows to forward port 4000 to WSL, allowing your Android device to access the API.

## Method 1: Complete Launcher with Port Forwarding (Recommended)

Right-click and **"Run as administrator"**:
```
start_with_portforward.bat
```

This will:
1. Set up port forwarding (Windows → WSL)
2. Add firewall rule for port 4000
3. Start the API server in WSL
4. Set up ADB reverse port forwarding (Android → Windows)
5. Launch Flutter on your Android device (R5CYA0A3JQF)

## Method 2: Regular Launch (After First-Time Setup)

Double-click `start_api_and_run.bat` or run from command line:

```bash
./start_api_and_run.bat
```

This will:
1. Start WSL and launch your API server in a new window
2. Wait 5 seconds for the API to start
3. Set up ADB reverse port forwarding (Android → Windows)
4. Launch Flutter on your Android device (R5CYA0A3JQF)

**Note**: Windows port forwarding persists across reboots, but ADB port forwarding is reset when you disconnect/reconnect USB or restart the device. This script automatically re-establishes ADB port forwarding each time.

## Method 2: Using PowerShell Script

Run from PowerShell:

```powershell
./start_api_and_run.ps1
```

If you get an execution policy error, run this first (one time only):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Method 3: Using VS Code Launch Configuration (Recommended for Development)

1. Open this project in VS Code
2. Press `F5` or go to Run → Start Debugging
3. Select **"Android (with API)"** from the dropdown
4. The API will automatically start before launching Flutter

Available configurations:
- **Android (with API)**: Starts the API server, then runs Flutter
- **Android (device only)**: Just runs Flutter (if API is already running)

## Method 4: Manual (Traditional Way)

If you prefer to start things manually:

### Terminal 1 - Start API:
```bash
wsl -d Ubuntu bash -c "cd /home/morgan/landledger && ./safe_api_start.sh"
```

### Terminal 2 - Run Flutter:
```bash
flutter run -d R5CYA0A3JQF
```

## Troubleshooting

### "Connection refused" or "No route to host" Error
If you see connection errors in the Flutter logs, it's usually because ADB reverse port forwarding was reset.

**Solution**: The launch scripts automatically set up ADB port forwarding, but if you started Flutter manually, run:
```bash
adb reverse tcp:4000 tcp:4000
```

Or use one of the launch scripts which handle this automatically.

If the error persists, verify Windows → WSL port forwarding is set up (one-time, requires admin):
1. Right-click `start_with_portforward.bat`
2. Select "Run as administrator"
3. This will configure port forwarding and firewall rules

**To verify it's working**:
```bash
netsh interface portproxy show all
```

You should see:
```
Listen on ipv4:             Connect to ipv4:
Address         Port        Address         Port
--------------- ----------  --------------- ----------
0.0.0.0         4000        172.x.x.x       4000
```

### Device Not Authorized
If you see "Device R5CYA0A3JQF is not authorized":
1. Check your Android device screen for the USB debugging authorization dialog
2. Tap "OK" and check "Always allow from this computer"

### API Not Starting
- Check WSL is installed: `wsl --list`
- Verify the script exists: `wsl -d Ubuntu-20.04 ls -la /home/morgan/landledger/safe_api_start.sh`
- Make sure the script is executable: `wsl -d Ubuntu-20.04 chmod +x /home/morgan/landledger/safe_api_start.sh`

### Port Already in Use
If the API port is already in use:
```bash
wsl -d Ubuntu-20.04 bash -c "cd /home/morgan/landledger && ./safe_api_stop.sh"
```

Then restart using one of the methods above.

### Firewall Blocking Connection
If port forwarding is set up but Android still can't connect:
1. Open Windows Defender Firewall
2. Check if "LandLedger API Port 4000" rule exists and is enabled
3. Or re-run `setup_port_forwarding.bat` as administrator
