import { Request, Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { JWT_SECRET, isAllowedAdminEmail } from '../config'
import { getDb, isDbConnected } from '../db'

export interface AuthUserPayload {
  userId: string
  email: string
  name: string
  role: 'landlord' | 'tenant'
  phone?: string
  tenantId?: string | null
  unitNumber?: string
  avatarInitials: string
  tv?: number
}

export interface PublicPaySessionPayload {
  purpose: 'public_pay_session'
  tenantId: string
  leaseId?: string | null
  unitNumber?: string
  phone?: string
  linkId?: string | null
}

export interface AuthRequest extends Request {
  user?: AuthUserPayload
  paySession?: PublicPaySessionPayload
}

function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers['authorization']
  if (typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
    return authHeader.slice(7).trim() || null
  }
  return null
}

async function isTokenVersionValid(userId: string, tokenTv?: number): Promise<boolean> {
  if (!isDbConnected()) return true
  try {
    const db = getDb()
    const userDoc = await db.collection('users').findOne(
      { id: userId },
      { projection: { tokenVersion: 1 } }
    )
    if (!userDoc) return true
    const currentTv = Number(userDoc.tokenVersion || 0)
    const claimedTv = Number(tokenTv ?? 0)
    return currentTv === claimedTv
  } catch {
    return true
  }
}

export async function authenticateToken(req: AuthRequest, res: Response, next: NextFunction) {
  const token = extractBearerToken(req)

  if (!token) {
    return res.status(401).json({ error: 'Authentication required. Please sign in.' })
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as any
    // Reject purpose-scoped tokens (OTP challenges, reset tokens, public pay tokens) from being used as full sessions
    if (decoded.purpose) {
      return res.status(403).json({ error: 'Invalid session token type.' })
    }
    if (!decoded.userId || !decoded.role) {
      return res.status(403).json({ error: 'Malformed authentication token.' })
    }
    if (decoded.role === 'landlord' && !isAllowedAdminEmail(decoded.email)) {
      return res.status(403).json({ error: 'Access denied: unauthorized administrator account.' })
    }
    const validVersion = await isTokenVersionValid(String(decoded.userId), decoded.tv)
    if (!validVersion) {
      return res.status(401).json({ error: 'Session has been revoked. Please sign in again.' })
    }
    req.user = decoded as AuthUserPayload
    next()
  } catch {
    return res.status(401).json({ error: 'Session expired or invalid authentication token.' })
  }
}

/**
 * Accepts EITHER a standard authenticated user JWT OR a verified `public_pay_session` JWT.
 * Used for payment status endpoints shared by logged-in users and OTP-verified public payment links.
 */
export async function authenticateUserOrPaySession(req: AuthRequest, res: Response, next: NextFunction) {
  const token = extractBearerToken(req) || (typeof req.body?.paySessionToken === 'string' ? req.body.paySessionToken : null)
  if (!token) {
    return res.status(401).json({ error: 'Authentication required.' })
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as any
    if (decoded.purpose === 'public_pay_session' && decoded.tenantId) {
      req.paySession = decoded as PublicPaySessionPayload
      return next()
    }
    if (!decoded.purpose && decoded.userId && decoded.role) {
      if (decoded.role === 'landlord' && !isAllowedAdminEmail(decoded.email)) {
        return res.status(403).json({ error: 'Access denied: unauthorized administrator account.' })
      }
      const validVersion = await isTokenVersionValid(String(decoded.userId), decoded.tv)
      if (!validVersion) {
        return res.status(401).json({ error: 'Session has been revoked. Please sign in again.' })
      }
      req.user = decoded as AuthUserPayload
      return next()
    }
    return res.status(403).json({ error: 'Invalid authorization token.' })
  } catch {
    return res.status(401).json({ error: 'Session expired or invalid token.' })
  }
}

export function requireRole(allowedRoles: ('landlord' | 'tenant')[]) {
  return (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Access denied: insufficient administrative permissions.' })
    }
    if (req.user.role === 'landlord' && !isAllowedAdminEmail(req.user.email)) {
      return res.status(403).json({ error: 'Access denied: administrator email is not on the approved policy.' })
    }
    next()
  }
}
