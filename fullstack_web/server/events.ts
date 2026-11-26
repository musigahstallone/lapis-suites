import { Request, Response } from 'express'
import jwt from 'jsonwebtoken'
import { JWT_SECRET, ALLOWED_CORS_ORIGINS, isAllowedAdminEmail } from './config'
import { logServerEvent } from './middleware/logger'

interface SSEClient {
  id: string
  res: Response
  userId: string
  role: string
  tenantId?: string
  unitNumber?: string
  email?: string
}

let clients: SSEClient[] = []

export function sseHandler(req: Request, res: Response) {
  // Require a valid authenticated user JWT (via ?token= for EventSource or Authorization header)
  const rawToken = (req.query.token as string) || (req.headers.authorization ? req.headers.authorization.replace(/^Bearer\s+/i, '') : null)
  if (!rawToken) {
    return res.status(401).json({ error: 'Authentication required for real-time events.' })
  }

  let decoded: any
  try {
    decoded = jwt.verify(rawToken, JWT_SECRET)
    if (decoded.purpose || !decoded.userId || !decoded.role) {
      return res.status(403).json({ error: 'Invalid authentication token for event stream.' })
    }
    if (decoded.role === 'landlord' && !isAllowedAdminEmail(decoded.email)) {
      return res.status(403).json({ error: 'Unauthorized administrator account.' })
    }
  } catch (err: any) {
    logServerEvent('SSE', `Rejected unauthenticated/expired SSE connection: ${err.message}`)
    return res.status(401).json({ error: 'Session expired or invalid token.' })
  }

  const origin = String(req.headers.origin || '').replace(/\/+$/, '')
  const allowedOrigin = origin && ALLOWED_CORS_ORIGINS.some((o) => o.toLowerCase() === origin.toLowerCase()) ? origin : ''

  // Set headers for Server-Sent Events (strict origin instead of wildcard `*`)
  const headers: Record<string, string> = {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  }
  if (allowedOrigin) {
    headers['Access-Control-Allow-Origin'] = allowedOrigin
    headers['Vary'] = 'Origin'
  }
  res.writeHead(200, headers)

  const userId: string = decoded.userId || decoded.id
  const role: string = decoded.role
  const tenantId: string | undefined = decoded.tenantId || undefined
  const unitNumber: string | undefined = decoded.unitNumber || undefined
  const email: string | undefined = decoded.email || undefined

  const clientId = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`
  const client: SSEClient = { id: clientId, res, userId, role, tenantId, unitNumber, email }
  clients.push(client)

  logServerEvent('SSE', `Client connected [${role} (${email || userId})] (ID: ${clientId}). Total active: ${clients.length}`)

  // Send initial handshake
  res.write(`data: ${JSON.stringify({ type: 'connected', clientId, role, timestamp: new Date().toISOString() })}\n\n`)

  // Heartbeat every 25s
  const heartbeat = setInterval(() => {
    try {
      res.write(':keepalive\n\n')
    } catch {
      clearInterval(heartbeat)
    }
  }, 25000)

  req.on('close', () => {
    clearInterval(heartbeat)
    clients = clients.filter(c => c.id !== clientId)
    logServerEvent('SSE', `Client disconnected (${clientId}). Remaining: ${clients.length}`)
  })
}

export function broadcastServerEvent(eventType: string, data: any) {
  if (clients.length === 0) return

  const payload = `event: ${eventType}\ndata: ${JSON.stringify(data)}\n\n`
  let deliveredCount = 0

  clients = clients.filter(client => {
    let shouldDeliver = true
    const isManagement = client.role === 'landlord' || client.role === 'admin'

    if (eventType === 'notification') {
      const targetUserId = data?.userId
      const targetTenantId = data?.tenantId
      const targetRole = data?.role

      if (isManagement) {
        // Landlord/Admin receives all management-directed notifications and their own
        shouldDeliver = targetRole === 'landlord' || targetRole === 'admin' || !targetRole || targetUserId === client.userId
      } else if (client.role === 'tenant') {
        // Tenant ONLY receives notifications specifically addressed to them
        shouldDeliver = Boolean(
          (targetUserId && client.userId && targetUserId === client.userId) ||
          (targetTenantId && client.tenantId && targetTenantId === client.tenantId)
        )
      } else {
        shouldDeliver = false
      }
    } else if (eventType === 'payment_received' || eventType === 'kcb_callback') {
      if (isManagement) {
        // Landlord/Admin receives ALL payment callbacks and notifications across portfolio
        shouldDeliver = true
      } else if (client.role === 'tenant') {
        // Resident ONLY receives payment callbacks initiated by their own account/unit
        const dataTenantId = data?.tenantId || data?.transaction?.tenantId || data?.lease?.tenantId
        const dataUserId = data?.userId || data?.callerUserId
        const dataUnit = data?.unitNumber || data?.transaction?.unitNumber || data?.lease?.unitNumber
        const dataPhone = data?.phoneNumber || data?.transaction?.phoneNumber

        shouldDeliver = Boolean(
          (dataTenantId && client.tenantId && dataTenantId === client.tenantId) ||
          (dataUserId && client.userId && dataUserId === client.userId) ||
          (dataUnit && client.unitNumber && dataUnit === client.unitNumber) ||
          (dataPhone && client.email && dataPhone === client.email)
        )
      } else {
        shouldDeliver = false
      }
    } else if (eventType === 'audit_updated') {
      // Audit ledger updates are management-only
      shouldDeliver = isManagement
    }

    if (!shouldDeliver) {
      return true // Keep connection alive, simply skip sending to this client
    }

    try {
      client.res.write(payload)
      deliveredCount++
      return true
    } catch {
      return false
    }
  })

  logServerEvent('SSE', `Dispatched event "${eventType}" to ${deliveredCount}/${clients.length} authenticated clients`)
}

export function getConnectedClientCount(): number {
  return clients.length
}
