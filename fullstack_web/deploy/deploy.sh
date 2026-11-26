#!/usr/bin/env bash
# ==============================================================================
# Automated Zero-Downtime Deployment Script for Lapis Suites Portal
# Usage: ./deploy/deploy.sh
# ==============================================================================

set -euo pipefail

APP_DIR="/var/www/lapissuites"
BRANCH="master"

echo "=========================================================="
echo "🚀 Starting Deployment of Lapis Suites Portal..."
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

cd "${APP_DIR}"

# 1. Pull latest code from repository
echo "📥 Pulling latest changes from branch: ${BRANCH}..."
git fetch origin ${BRANCH}
git reset --hard origin/${BRANCH}

# 2. Install dependencies
echo "📦 Installing Node.js dependencies..."
npm ci --prefer-offline --no-audit

# 3. Build Vite Frontend for production
echo "🔨 Building frontend assets with Vite..."
npm run build

# 4. Ensure logs directory exists for PM2
mkdir -p logs

# 5. Reload backend API with PM2
echo "🔄 Reloading backend service via PM2..."
if pm2 describe lapis-suites-api > /dev/null 2>&1; then
    pm2 reload ecosystem.config.cjs --update-env
else
    pm2 start ecosystem.config.cjs
fi

# Save PM2 state for automatic reboot persistence
pm2 save

# 6. Verify Health Endpoint
echo "🔍 Verifying backend API health..."
sleep 2
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/api/health || true)

if [ "${HEALTH_STATUS}" -eq 200 ]; then
    echo "✅ Health check PASSED: Backend API is online and MongoDB connected."
else
    echo "⚠️ Warning: Health check returned HTTP ${HEALTH_STATUS}. Please inspect logs: pm2 logs lapis-suites-api"
fi

# 7. Reload Nginx if configuration changed
if nginx -t > /dev/null 2>&1; then
    echo "🌐 Reloading Nginx..."
    systemctl reload nginx
fi

echo "=========================================================="
echo "✨ Deployment Complete! Live on production."
echo "=========================================================="
