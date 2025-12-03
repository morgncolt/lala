module.exports = {
  apps: [{
    name: "landledger-api",
    script: "./server.js",
    cwd: "/home/morgan/landledger/api",
    env: {
      NODE_ENV: "production",
      API_PORT: "4000",
      // IMPORTANT: do not set PORT here (CouchDB uses it). We use API_PORT.
      CHANNEL: "mychannel",
      CC_NAME: "landledger",
      IDENTITY: "appUser",
      CCP_PATH: "/home/morgan/landledger/api/connection/connection-org1.json",
      WALLET_DIR: "/home/morgan/landledger/api/wallet",
      FABRIC_DISCOVERY: "try",
      FABRIC_AS_LOCALHOST: "true",
      REUSE_GATEWAY: "true",
      API_CACHE_TTL_MS: "1500",
      // Give the app up to 8s to shut down gracefully before PM2 forces a kill
      SHUTDOWN_TIMEOUT_MS: "8000"
    },
    watch: false,
    max_restarts: 20,
    exp_backoff_restart_delay: 2000,
    // Increase kill_timeout to allow graceful disconnects (should be > SHUTDOWN_TIMEOUT_MS)
    kill_timeout: 10000
  }]
}
