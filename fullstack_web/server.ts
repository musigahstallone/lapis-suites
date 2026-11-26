import 'dotenv/config'
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
import { startReminderScheduler } from './server/services/reminders'

// Recreate __dirname for ES modules
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const app = express()

// Security baseline: hide Express fingerprint, trust 1 reverse-proxy hop (Cloudflare Tunnel / Nginx), disable 304 caching
app.disable('x-powered-by')
app.set('trust proxy', 1)
app.set('etag', false)

// 1. Global Security & Parsing Middleware (must be registered BEFORE routes)
app.use(securityHeaders)
app.use(cors(buildCorsOptions()))
app.use(express.json({
  limit: '2mb',
  verify: (req: any, _res, buf) => {
    req.rawBody = buf.toString('utf8')
  }
}))
app.use(express.text({ limit: '2mb', type: ['text/*', 'application/octet-stream', 'application/x-www-form-urlencoded'] }))
app.use(nosqlSanitizer)
app.use(httpLogger)

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

// Database availability guard
app.use('/api', requireDb)

// Realtime Server-Sent Events Endpoint (authenticated inside sseHandler)
app.get('/api/events', sseHandler)

// 2. Register Modular REST Endpoints FIRST
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

// 3. Serve static published files from the dist folder AFTER api routes
const distPath = path.join(__dirname, 'dist')
app.use(express.static(distPath))

// 4. Catch-all route LAST (handles client-side routing)
app.get('*path', (req, res, next) => {
  if (req.path.startsWith('/api')) {
    return next()
  }
  res.sendFile(path.join(distPath, 'index.html'))
})

// 5. Global Error Handler Middleware (never leak stack traces or internal DB details in production)
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  const status = Number(err.status) || (err.message?.includes('CORS') ? 403 : 500)
  logServerEvent('ERROR', `[${status}] ${err.message || 'Internal server error'}`)
  const clientMessage = status >= 500 && IS_PRODUCTION
    ? 'Internal server error. Please try again shortly.'
    : (err.message || 'Internal server error')
  res.status(status).json({ error: clientMessage })
})

// Start Server
app.listen(PORT, async () => {
  logServerEvent('SERVER', `Lapis Suites backend API listening on http://localhost:${PORT}`)
  try {
    await connectMongo()
    startReminderScheduler()
  } catch (err: any) {
    logServerEvent('SERVER', `Database connection warning: ${err.message}`)
  }
})

export default app
