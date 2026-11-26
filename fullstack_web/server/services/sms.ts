import { getDb, isDbConnected } from '../db'
import {
  MOBILESASA_CONFIG,
  MAX_ADMIN_ACCOUNTS,
  isAllowedAdminEmail,
  generateHexObjectId,
  normalizeKenyanPhone
} from '../config'
import { logServerEvent } from '../middleware/logger'

export type SmsPurpose =
  | 'admin_login_otp'
  | 'admin_stk_otp'
  | 'password_reset_otp'
  | 'payment_link_otp'
  | 'payment_receipt'
  | 'payment_landlord_alert'
  | 'rent_reminder'
  | 'maintenance_alert'
  | 'maintenance_update'
  | 'lease_notice'
  | 'notification'
  | 'general'

export interface SendSmsOptions {
  phone: string
  message: string
  trackingId?: string
  callbackUrl?: string
  purpose?: SmsPurpose
  recipientEmail?: string
  userId?: string
  meta?: Record<string, any>
}

export interface SendSmsResult {
  ok: boolean
  configured: boolean
  trackingId: string
  messageId?: string
  cost?: number
  responseCode?: string
  statusText?: string
  error?: string
}

export interface BulkRecipient {
  phone: string
  message: string
}

export interface SendBulkSmsOptions {
  recipients: BulkRecipient[]
  callbackUrl?: string
  purpose?: string
}

export interface SendBulkSmsResult {
  ok: boolean
  configured: boolean
  bulkId?: string
  responseCode?: string
  recipientCount: number
  error?: string
}

/**
 * Single SMS via MobileSasa v2 API (`POST /v2/send/message`).
 * Supplies a deterministic `trackingId` so DLR webhooks join cleanly to MongoDB `sms_logs`.
 */
export async function sendSms(options: SendSmsOptions): Promise<SendSmsResult> {
  const trackingId = options.trackingId || `lapis-${generateHexObjectId()}`
  const normalizedPhone = normalizeKenyanPhone(options.phone)
  const nowIso = new Date().toISOString()

  if (!normalizedPhone || !/^254[17]\d{8}$/.test(normalizedPhone)) {
    return {
      ok: false,
      configured: Boolean(MOBILESASA_CONFIG.token),
      trackingId,
      error: 'Invalid Kenyan phone number format. Use 07..., 01..., or +2547... format.'
    }
  }

  const effectiveCallbackUrl = (options.callbackUrl || MOBILESASA_CONFIG.callbackUrl || '').trim()

  const logDoc: Record<string, any> = {
    id: generateHexObjectId(),
    type: 'single',
    trackingId,
    messageId: null,
    phone: normalizedPhone,
    senderId: MOBILESASA_CONFIG.senderId,
    purpose: options.purpose || 'general',
    recipientEmail: options.recipientEmail || null,
    userId: options.userId || null,
    // Do not store plaintext OTP codes in SMS logs if it's an OTP message
    messagePreview: options.purpose?.includes('otp') ? '[OTP Message Redacted]' : options.message.slice(0, 160),
    status: 'Pending',
    responseCode: null,
    costParts: null,
    costKes: null,
    deliveryStatus: null,
    deliveryTime: null,
    gateway: null,
    deliveryCode: null,
    callbackUrl: effectiveCallbackUrl || null,
    meta: options.meta || null,
    dlrHistory: [],
    createdAt: nowIso,
    updatedAt: nowIso
  }

  if (!MOBILESASA_CONFIG.token) {
    logDoc.status = 'NotConfigured'
    logDoc.deliveryStatus = 'MOBILESASA_TOKEN missing in environment'
    await persistSmsLog(logDoc)
    logServerEvent('SMS', `MOBILESASA_TOKEN is not configured; skipped SMS dispatch to ${normalizedPhone} [${trackingId}]`)
    return {
      ok: false,
      configured: false,
      trackingId,
      error: 'SMS service is not configured. Set MOBILESASA_TOKEN in .env.'
    }
  }

  const payload: Record<string, any> = {
    senderID: MOBILESASA_CONFIG.senderId,
    phone: normalizedPhone,
    message: options.message,
    trackingId
  }

  if (effectiveCallbackUrl && /^https?:\/\//i.test(effectiveCallbackUrl)) {
    payload.callbackUrl = effectiveCallbackUrl.slice(0, 255)
  }

  try {
    const response = await fetch(`${MOBILESASA_CONFIG.baseUrl}/v2/send/message`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MOBILESASA_CONFIG.token}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify(payload)
    })

    const rawText = await response.text()
    let data: any = {}
    try {
      data = rawText ? JSON.parse(rawText) : {}
    } catch {
      data = { status: false, message: rawText || `HTTP ${response.status}` }
    }

    const accepted = response.ok && (data.status === true || data.responseCode === '0200')
    logDoc.status = accepted ? 'Accepted' : 'Failed'
    logDoc.responseCode = data.responseCode || String(response.status)
    logDoc.messageId = data.messageId || null
    logDoc.costParts = typeof data.cost === 'number' ? data.cost : null
    logDoc.deliveryStatus = data.message || (accepted ? 'Accepted' : `HTTP ${response.status}`)
    logDoc.updatedAt = new Date().toISOString()

    await persistSmsLog(logDoc)

    if (accepted) {
      logServerEvent('SMS', `Dispatched SMS (${options.purpose || 'general'}) to ${normalizedPhone} | trackingId=${trackingId} | messageId=${data.messageId || 'n/a'} | parts=${data.cost ?? 'n/a'}`)
      return {
        ok: true,
        configured: true,
        trackingId,
        messageId: data.messageId,
        cost: data.cost,
        responseCode: data.responseCode,
        statusText: data.message
      }
    }

    const errMsg = formatMobileSasaError(data.responseCode, data.message)
    logServerEvent('SMS', `MobileSasa rejected SMS to ${normalizedPhone} (${data.responseCode || response.status}): ${errMsg}`)
    return {
      ok: false,
      configured: true,
      trackingId,
      responseCode: data.responseCode,
      error: errMsg
    }
  } catch (err: any) {
    logDoc.status = 'Failed'
    logDoc.deliveryStatus = err.message || 'Network error'
    logDoc.updatedAt = new Date().toISOString()
    await persistSmsLog(logDoc)
    logServerEvent('SMS', `Network error sending SMS to ${normalizedPhone}: ${err.message}`)
    return {
      ok: false,
      configured: true,
      trackingId,
      error: `Failed to reach MobileSasa gateway: ${err.message}`
    }
  }
}

/**
 * Personalized Bulk SMS via MobileSasa (`POST /v1/send/bulk-personalized`).
 * Ready for future rent reminders and announcements.
 */
export async function sendBulkSms(options: SendBulkSmsOptions): Promise<SendBulkSmsResult> {
  const cleanedRecipients = (options.recipients || [])
    .map((r) => ({
      phone: normalizeKenyanPhone(r.phone),
      message: String(r.message || '').trim()
    }))
    .filter((r) => /^254[17]\d{8}$/.test(r.phone) && r.message.length > 0)

  if (cleanedRecipients.length === 0) {
    return {
      ok: false,
      configured: Boolean(MOBILESASA_CONFIG.token),
      recipientCount: 0,
      error: 'No valid recipient phone numbers and messages provided.'
    }
  }

  if (!MOBILESASA_CONFIG.token) {
    return {
      ok: false,
      configured: false,
      recipientCount: cleanedRecipients.length,
      error: 'SMS service is not configured. Set MOBILESASA_TOKEN in .env.'
    }
  }

  const effectiveCallbackUrl = (options.callbackUrl || MOBILESASA_CONFIG.callbackUrl || '').trim()
  const payload: Record<string, any> = {
    senderID: MOBILESASA_CONFIG.senderId,
    messageBody: cleanedRecipients
  }
  if (effectiveCallbackUrl && /^https?:\/\//i.test(effectiveCallbackUrl)) {
    payload.callbackUrl = effectiveCallbackUrl.slice(0, 255)
  }

  const nowIso = new Date().toISOString()
  try {
    const response = await fetch(`${MOBILESASA_CONFIG.baseUrl}/v1/send/bulk-personalized`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MOBILESASA_CONFIG.token}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify(payload)
    })

    const data: any = await response.json().catch(() => ({}))
    const accepted = response.ok && (data.status === true || data.responseCode === '0200')

    await persistSmsLog({
      id: generateHexObjectId(),
      type: 'bulk_personalized',
      trackingId: data.bulkId || `bulk-${generateHexObjectId()}`,
      bulkId: data.bulkId || null,
      senderId: MOBILESASA_CONFIG.senderId,
      purpose: options.purpose || 'bulk_notification',
      recipientCount: cleanedRecipients.length,
      status: accepted ? 'Accepted' : 'Failed',
      responseCode: data.responseCode || String(response.status),
      deliveryStatus: data.message || (accepted ? 'Accepted' : `HTTP ${response.status}`),
      callbackUrl: effectiveCallbackUrl || null,
      dlrHistory: [],
      createdAt: nowIso,
      updatedAt: nowIso
    })

    if (!accepted) {
      return {
        ok: false,
        configured: true,
        recipientCount: cleanedRecipients.length,
        responseCode: data.responseCode,
        error: formatMobileSasaError(data.responseCode, data.message)
      }
    }

    logServerEvent('SMS', `Dispatched bulk personalized SMS to ${cleanedRecipients.length} recipients | bulkId=${data.bulkId}`)
    return {
      ok: true,
      configured: true,
      bulkId: data.bulkId,
      responseCode: data.responseCode,
      recipientCount: cleanedRecipients.length
    }
  } catch (err: any) {
    logServerEvent('SMS', `Bulk SMS network error: ${err.message}`)
    return {
      ok: false,
      configured: true,
      recipientCount: cleanedRecipients.length,
      error: `Failed to reach MobileSasa gateway: ${err.message}`
    }
  }
}

async function persistSmsLog(doc: Record<string, any>) {
  try {
    if (!isDbConnected()) return
    const db = getDb()
    await db.collection('sms_logs').insertOne(doc)
  } catch (err: any) {
    logServerEvent('SMS', `Warning: Could not persist SMS log: ${err.message}`)
  }
}

function formatMobileSasaError(code?: string, message?: string): string {
  if (code === '0402') return 'Insufficient MobileSasa SMS balance. Please top up your SMS credits.'
  if (code === '0409') return 'Duplicate SMS blocked by carrier. Please wait before requesting another code.'
  if (code === '0422') return message || 'Invalid SMS recipient or sender parameters.'
  return message || 'MobileSasa SMS gateway rejected the request.'
}

/**
 * Collect unique, valid Kenyan phone numbers for the authorized landlord/admin accounts (max 2)
 * strictly from MongoDB Settings / Users (not .env).
 */
export async function getAuthorizedAdminPhones(): Promise<string[]> {
  const phones = new Set<string>()
  const addIfValid = (raw?: string) => {
    if (!raw) return
    const normalized = normalizeKenyanPhone(raw)
    if (/^254[17]\d{8}$/.test(normalized)) {
      phones.add(normalized)
    }
  }

  try {
    if (isDbConnected()) {
      const db = getDb()
      const admins = await db.collection('users')
        .find({ role: 'landlord' })
        .sort({ createdAt: 1, _id: 1 })
        .toArray()

      const allowed = admins
        .filter((u: any) => isAllowedAdminEmail(u.email))
        .slice(0, MAX_ADMIN_ACCOUNTS)

      for (const admin of allowed) {
        addIfValid(admin.phone)
      }
    }
  } catch (err: any) {
    logServerEvent('SMS', `Warning resolving admin phones from DB: ${err.message}`)
  }

  return Array.from(phones)
}

/**
 * Fire-and-forget helper to send an SMS alert to all authorized admin phone numbers.
 */
export async function notifyAdminsSms(
  message: string,
  purpose: SmsPurpose = 'notification',
  meta?: Record<string, any>
): Promise<void> {
  try {
    const adminPhones = await getAuthorizedAdminPhones()
    if (adminPhones.length === 0) {
      logServerEvent('SMS', `Skipped admin SMS (${purpose}): no admin phone numbers configured.`)
      return
    }
    await Promise.allSettled(
      adminPhones.map((phone) =>
        sendSms({
          phone,
          message,
          purpose,
          meta
        })
      )
    )
  } catch (err: any) {
    logServerEvent('SMS', `Admin SMS dispatch warning (${purpose}): ${err.message}`)
  }
}

/**
 * Fire-and-forget helper to send an SMS notification to a resident/tenant phone number.
 */
export async function notifyTenantSms(
  phone: string | undefined | null,
  message: string,
  purpose: SmsPurpose = 'notification',
  extra?: { recipientEmail?: string; userId?: string; meta?: Record<string, any> }
): Promise<SendSmsResult | null> {
  try {
    if (!phone) return null
    const normalized = normalizeKenyanPhone(phone)
    if (!/^254[17]\d{8}$/.test(normalized)) return null
    return await sendSms({
      phone: normalized,
      message,
      purpose,
      recipientEmail: extra?.recipientEmail,
      userId: extra?.userId,
      meta: extra?.meta
    })
  } catch (err: any) {
    logServerEvent('SMS', `Tenant SMS dispatch warning (${purpose}): ${err.message}`)
    return null
  }
}
