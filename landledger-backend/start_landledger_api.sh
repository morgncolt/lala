#!/bin/bash

# LandLedger Backend API Startup Script
# This script starts the Node.js backend server on all network interfaces

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "  LandLedger Backend API Startup"
echo "========================================="
echo ""

# Check if node is installed
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed"
    echo "Please install Node.js from https://nodejs.org/"
    exit 1
fi

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo "❌ Error: package.json not found in $SCRIPT_DIR"
    exit 1
fi

# Check if node_modules exists, if not run npm install
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    if [ $? -ne 0 ]; then
        echo "❌ Error: Failed to install dependencies"
        exit 1
    fi
fi

# Kill any existing process on port 4000
echo "🔍 Checking for existing processes on port 4000..."
PID=$(lsof -ti:4000 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo "⚠️  Found existing process on port 4000 (PID: $PID)"
    echo "🛑 Stopping existing process..."
    kill -9 $PID
    sleep 1
fi

# Get local IP address
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================="
echo "🚀 Starting LandLedger Backend API..."
echo "========================================="
echo "📍 Local:   http://localhost:4000"
echo "🌐 Network: http://$LOCAL_IP:4000"
echo "📱 Android: http://192.168.0.23:4000"
echo "========================================="
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start the server
node server.js
