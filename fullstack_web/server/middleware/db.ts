import { Request, Response, NextFunction } from 'express'
import { isDbConnected, getDb } from '../db'
import type { Db } from 'mongodb'

export interface DbRequest extends Request {
  db: Db
}

export function requireDb(req: Request, res: Response, next: NextFunction) {
  if (!isDbConnected()) {
    return res.status(503).json({ error: 'Database service unavailable' })
  }
  ;(req as any).db = getDb()
  next()
}
