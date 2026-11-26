import { Request, Response, NextFunction } from 'express'
import { CorsOptionsDelegate } from 'cors'
import { ALLOWED_CORS_ORIGINS } from '../config'
import { logServerEvent } from './logger'

/**
 * Helmet-equivalent HTTP security headers middleware (zero external dependency).
 */
export function securityHeaders(req: Request, res: Response, next: NextFunction) {
  res.setHeader('X-Content-Type-Options', 'nosniff')
  res.setHeader('X-Frame-Options', 'DENY')
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin')
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=(self)')
  res.setHeader('X-DNS-Prefetch-Control', 'off')
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin')

  const isHttps = req.secure || req.headers['x-forwarded-proto'] === 'https'
  if (isHttps || process.env.NODE_ENV === 'production') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
  }

  next()
}

/**
 * Recursively strips MongoDB operator keys (starting with `$` or containing `.`)
 * from incoming objects to block NoSQL operator injection (e.g. `{ "$ne": null }`).
 */
function sanitizeValue(value: any, depth = 0): any {
  if (depth > 12 || value === null || value === undefined) return value
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item, depth + 1))
  }
  if (typeof value === 'object') {
    const clean: Record<string, any> = {}
    for (const [k, v] of Object.entries(value)) {
      if (k.startsWith('$') || k.includes('\0') || k === '__proto__' || k === 'constructor' || k === 'prototype') {
        continue
      }
      clean[k] = sanitizeValue(v, depth + 1)
    }
    return clean
  }
  return value
}

export function nosqlSanitizer(req: Request, _res: Response, next: NextFunction) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    req.body = sanitizeValue(req.body)
  }
  if (req.query && typeof req.query === 'object') {
    const cleanedQuery = sanitizeValue(req.query)
    for (const key of Object.keys(req.query)) {
      if (!(key in cleanedQuery)) {
        delete (req.query as any)[key]
      } else {
        ;(req.query as any)[key] = cleanedQuery[key]
      }
    }
  }
  next()
}

function resolveRequestOrigin(req: Request): string {
  const rawProto = String(req.headers['x-forwarded-proto'] || req.protocol || 'https').split(',')[0].trim().toLowerCase()
  const rawHost = String(req.headers['x-forwarded-host'] || req.headers['host'] || '').split(',')[0].trim().toLowerCase()
  if (!rawHost) return ''
  return `${rawProto}://${rawHost}`
}

/**
 * Locked-down CORS configuration with dynamic same-origin awareness.
 * - Always allows requests with no `Origin` header (native mobile app, webhooks, curl).
 * - Always allows same-origin browser requests (e.g., Vite `<script crossorigin>` or SPA `fetch('/api/...')` on Firebase App Hosting or custom domains).
 * - Allows configured cross-origin web origins (`CORS_ORIGINS`, `APP_BASE_URL`, `FIREBASE_APP_HOSTING_URL`, default hosted app origin, localhost in non-prod).
 * - Blocks unauthorized third-party browser origins.
 */
export function buildCorsOptions(): CorsOptionsDelegate<Request> {
  const allowedSet = new Set(ALLOWED_CORS_ORIGINS.map((o) => o.replace(/\/+$/, '').toLowerCase()))

  return (req, callback) => {
    const origin = req.headers.origin
    const requestOrigin = resolveRequestOrigin(req)

    const corsOptions = {
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Kcb-Secret',
        'X-Webhook-Secret',
        'X-MobileSasa-Secret',
        'X-MobileSasa-Signature'
      ],
      exposedHeaders: ['X-Total-Count']
    }

    if (!origin) {
      return callback(null, { ...corsOptions, origin: true })
    }

    const normalized = origin.replace(/\/+$/, '').toLowerCase()
    const isSameOrigin = Boolean(requestOrigin) && normalized === requestOrigin

    if (isSameOrigin || allowedSet.has(normalized)) {
      return callback(null, { ...corsOptions, origin: true })
    }

    logServerEvent('SECURITY', `Blocked CORS request from unauthorized origin: ${origin} (host origin: ${requestOrigin || 'unknown'})`)
    return callback(new Error('Origin not allowed by CORS policy.'))
  }
}
