import { Request, Response, NextFunction } from 'express'
import { getClientIp } from '../config'

export function logServerEvent(category: string, message: string, meta?: any) {
  const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19)
  const metaStr = meta ? ` | ${typeof meta === 'object' ? JSON.stringify(meta) : meta}` : ''
  console.log(`[${timestamp}] [${category.toUpperCase()}] ${message}${metaStr}`)
}

export function httpLogger(req: Request, res: Response, next: NextFunction) {
  const start = Date.now()
  const ip = getClientIp(req)

  res.on('finish', () => {
    const duration = Date.now() - start
    const status = res.statusCode
    const statusTag = status >= 500 ? 'ERR' : status >= 400 ? 'WARN' : 'OK'
    logServerEvent('HTTP', `${req.method} ${req.originalUrl || req.url} - ${status} (${duration}ms) [IP: ${ip}] [${statusTag}]`)
  })
  next()
}
