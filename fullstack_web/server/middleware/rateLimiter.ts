import { Request, Response, NextFunction } from 'express'
import { getClientIp } from '../config'
import { logServerEvent } from './logger'

interface RateLimitRecord {
  count: number
  resetTime: number
}

const rateLimitMap = new Map<string, RateLimitRecord>()

// Periodically prune expired entries so memory never grows unbounded
const pruneTimer = setInterval(() => {
  const now = Date.now()
  for (const [key, rec] of rateLimitMap.entries()) {
    if (now > rec.resetTime) {
      rateLimitMap.delete(key)
    }
  }
}, 5 * 60 * 1000)
if (typeof pruneTimer.unref === 'function') pruneTimer.unref()

export interface RateLimiterOptions {
  keyGenerator?: (req: Request, ip: string) => string
  message?: string
}

export function createRateLimiter(
  maxRequests: number,
  windowMs: number,
  options?: RateLimiterOptions
) {
  return (req: Request, res: Response, next: NextFunction) => {
    const ip = getClientIp(req)
    const key = options?.keyGenerator
      ? options.keyGenerator(req, ip)
      : `${req.baseUrl}${req.path}:${ip}`
    const now = Date.now()
    const record = rateLimitMap.get(key)

    if (!record || now > record.resetTime) {
      rateLimitMap.set(key, { count: 1, resetTime: now + windowMs })
      return next()
    }

    record.count++
    if (record.count > maxRequests) {
      const retryAfterSec = Math.max(1, Math.ceil((record.resetTime - now) / 1000))
      res.setHeader('Retry-After', String(retryAfterSec))
      logServerEvent(
        'SECURITY',
        `Rate limit exceeded for IP: ${ip} on ${req.baseUrl}${req.path} (${record.count} reqs)`,
        { ip, path: `${req.baseUrl}${req.path}` }
      )
      return res.status(429).json({
        error: options?.message || 'Too many requests. Please wait a moment and try again.'
      })
    }
    next()
  }
}
