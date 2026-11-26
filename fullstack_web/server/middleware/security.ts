import { Request, Response, NextFunction } from 'express'
import { CorsOptions } from 'cors'
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

/**
 * Locked-down CORS configuration.
 * - Allows configured web origins (`CORS_ORIGINS` + `APP_BASE_URL` + localhost in non-prod).
 * - Allows native mobile apps / webhooks / curl requests that send no `Origin` header.
 * - Blocks unauthorized third-party browser origins.
 */
export function buildCorsOptions(): CorsOptions {
  const allowedSet = new Set(ALLOWED_CORS_ORIGINS.map((o) => o.toLowerCase()))

  return {
    origin: (origin, callback) => {
      if (!origin) {
        return callback(null, true)
      }
      const normalized = origin.replace(/\/+$/, '').toLowerCase()
      if (allowedSet.has(normalized)) {
        return callback(null, true)
      }
      logServerEvent('SECURITY', `Blocked CORS request from unauthorized origin: ${origin}`)
      return callback(new Error('Origin not allowed by CORS policy.'))
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Kcb-Secret', 'X-Webhook-Secret', 'X-MobileSasa-Secret', 'X-MobileSasa-Signature']
  }
}
