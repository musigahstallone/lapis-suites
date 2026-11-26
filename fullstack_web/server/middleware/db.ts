import { Request, Response, NextFunction } from 'express'
import { isDbConnected, getDb, ensureDbConnected } from '../db'
import type { Db } from 'mongodb'

export interface DbRequest extends Request {
  db: Db
}

export async function requireDb(req: Request, res: Response, next: NextFunction) {
  // Always let /api/health respond cleanly with database status instead of a hard 503 block
  if (req.path === '/health') {
    return next()
  }

  if (!isDbConnected()) {
    const recovered = await ensureDbConnected()
    if (!recovered || !isDbConnected()) {
      return res.status(503).json({ error: 'Database service unavailable' })
    }
  }

  ;(req as any).db = getDb()
  next()
}
