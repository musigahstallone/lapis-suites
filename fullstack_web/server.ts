import 'dotenv/config'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import express, { Request, Response, NextFunction } from 'express'
import cors from 'cors'
import { PORT, IS_PRODUCTION } from './server/config'
import { connectMongo } from './server/db'
import { logServerEvent, httpLogger } from './server/middleware/logger'
import { sseHandler } from './server/events'
import { requireDb } from './server/middleware/db'
import { securityHeaders, nosqlSanitizer, buildCorsOptions } from './server/middleware/security'
import { createRateLimiter } from './server/middleware/rateLimiter'

// Modular Route Controllers
import authRoutes from './server/routes/auth'
import unitRoutes from './server/routes/units'
import tenantRoutes from './server/routes/tenants'
import leaseRoutes from './server/routes/leases'
import transactionRoutes from './server/routes/transactions'
import maintenanceRoutes from './server/routes/maintenance'
import notificationRoutes from './server/routes/notifications'
import kcbRoutes from './server/routes/kcb'
import smsRoutes from './server/routes/sms'
import publicPayRoutes, { recordPaymentLinkClick } from './server/routes/publicPay'
import settingsRoutes from './server/routes/settings'
import dashboardRoutes from './server/routes/dashboard'
import importRoutes from './server/routes/import'
import auditRoutes from './server/services/audit'
import { startReminderScheduler } from './server/services/reminders'

// Recreate __dirname for ES modules
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const app = express()

// Security baseline: hide Express fingerprint, trust reverse-proxy hops (Firebase App Hosting / Cloud Run / Cloudflare), disable 304 caching
app.disable('x-powered-by')
app.set('trust proxy', true)
app.set('etag', false)

// Resolve built Vite dist directory reliably (works regardless of working directory)
const primaryDistPath = path.join(__dirname, 'dist')
const distPath = fs.existsSync(path.join(primaryDistPath, 'index.html'))
  ? primaryDistPath
  : path.resolve(process.cwd(), 'dist')
const distIndexPath = path.join(distPath, 'index.html')

// 1. Global Security Headers & Request Logging
app.use(securityHeaders)
app.use(httpLogger)

// 2. Serve built static Vite assets FIRST (never blocked by API CORS or DB guards)
app.use(express.static(distPath, {
  index: 'index.html',
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('index.html')) {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate')
    } else if (filePath.includes(`${path.sep}assets${path.sep}`)) {
      res.setHeader('Cache-Control', 'public, max-age=31536000, immutable')
    }
  }
}))

// 3. API Parsing, CORS, Sanitization & Rate Limiting (scoped to /api and /p)
const apiCors = cors(buildCorsOptions())
app.use('/api', apiCors)
app.use(express.json({
  limit: '2mb',
  verify: (req: any, _res, buf) => {
    req.rawBody = buf.toString('utf8')
  }
}))
app.use(express.text({ limit: '2mb', type: ['text/*', 'application/octet-stream', 'application/x-www-form-urlencoded'] }))
app.use(nosqlSanitizer)

// Global API rate limiter (180 requests / minute per IP) — route-specific limiters remain stricter
const globalApiLimiter = createRateLimiter(180, 60 * 1000, {
  keyGenerator: (_req, ip) => `global:${ip}`
})

// Guarantee fresh, non-stale data on all API endpoints + apply global rate limit
app.use('/api', globalApiLimiter, (_req, res, next) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate')
  res.setHeader('Pragma', 'no-cache')
  res.setHeader('Expires', '0')
  next()
})

// Database availability guard (/api/health bypasses hard 503 and self-heals)
app.use('/api', requireDb)

// Realtime Server-Sent Events Endpoint (authenticated inside sseHandler)
app.get('/api/events', sseHandler)

// 4. Register Modular REST Endpoints
app.use('/api/auth', authRoutes)
app.use('/api', authRoutes)
app.use('/api', unitRoutes)
app.use('/api', tenantRoutes)
app.use('/api', leaseRoutes)
app.use('/api', transactionRoutes)
app.use('/api', maintenanceRoutes)
app.use('/api', notificationRoutes)
app.use('/api', kcbRoutes)
app.use('/api', smsRoutes)
app.use('/api', publicPayRoutes)
app.use('/api', settingsRoutes)
app.use('/api', dashboardRoutes)
app.use('/api', importRoutes)
app.use('/api', auditRoutes)

// Short tracked payment link redirect: records click immediately & routes to public OTP payment page
app.get('/p/:linkId', async (req, res) => {
  const linkId = String(req.params.linkId || '').trim()
  if (linkId) {
    try {
      const ip = (req.ip || req.socket.remoteAddress || '127.0.0.1').replace(/^::ffff:/, '')
      await recordPaymentLinkClick(linkId, ip, String(req.headers['user-agent'] || ''))
    } catch (err: any) {
      logServerEvent('PAY-LINK', `Click tracking notice for ${linkId}: ${err.message}`)
    }
  }
  res.redirect(302, `/#/pay/${encodeURIComponent(linkId)}`)
})

// 5. SPA Catch-all route LAST (serves index.html for client-side routes; returns 404 for missing API or static asset files)
const STATIC_ASSET_EXT_RE = /\.(js|mjs|cjs|css|map|png|jpe?g|gif|svg|webp|ico|woff2?|ttf|eot|json|txt|xml)$/i
app.get('*path', (req, res, next) => {
  if (req.path.startsWith('/api')) {
    return res.status(404).json({ error: 'API endpoint not found.' })
  }
  if (req.path.startsWith('/assets/') || STATIC_ASSET_EXT_RE.test(req.path)) {
    return res.status(404).send('Asset not found')
  }
  if (!fs.existsSync(distIndexPath)) {
    logServerEvent('SERVER', `ERROR: Built SPA entry not found at ${distIndexPath}. Ensure "npm run build" ran before starting the server.`)
    return res.status(500).send('Application frontend build not found.')
  }
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate')
  res.sendFile(distIndexPath, (err) => {
    if (err) next(err)
  })
})

// 6. Global Error Handler Middleware (never leak stack traces or internal DB details in production)
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  const status = Number(err.status) || (err.message?.includes('CORS') ? 403 : 500)
  logServerEvent('ERROR', `[${status}] ${err.message || 'Internal server error'}`)
  const clientMessage = status >= 500 && IS_PRODUCTION
    ? 'Internal server error. Please try again shortly.'
    : (err.message || 'Internal server error')
  res.status(status).json({ error: clientMessage })
})

// Start Server (bind 0.0.0.0 so Cloud Run / Firebase App Hosting routes traffic properly)
const listenPort = Number(PORT) || 3001
app.listen(listenPort, '0.0.0.0', async () => {
  logServerEvent('SERVER', `Lapis Suites backend API listening on http://0.0.0.0:${listenPort} (NODE_ENV=${process.env.NODE_ENV || 'development'}, dist=${fs.existsSync(distIndexPath) ? 'ready' : 'missing'})`)
  try {
    await connectMongo()
    startReminderScheduler()
  } catch (err: any) {
    logServerEvent('SERVER', `Initial database connection failed (will retry lazily on requests): ${err.message}`)
  }
})

export default app
