import crypto from 'crypto'
import { Request } from 'express'

export const IS_PRODUCTION = process.env.NODE_ENV === 'production'
export const PORT = process.env.PORT || 3001

// Strict JWT secret loading — NEVER hardcode production signing secrets in source code
const WEAK_PLACEHOLDERS = new Set([
  '',
  'your_production_secure_jwt_secret_key_here',
  'lapis_suites_jwt_secret_2026_production_key_#9821',
  'secret',
  'changeme'
])

function resolveJwtSecret(): string {
  const envSecret = (process.env.JWT_SECRET || '').trim()
  if (!envSecret || WEAK_PLACEHOLDERS.has(envSecret) || envSecret.length < 32) {
    if (IS_PRODUCTION) {
      throw new Error('CRITICAL: JWT_SECRET must be set in environment variables and be at least 32 characters long.')
    }
    // In local development only, generate an ephemeral per-process secret and warn loudly
    console.warn('[SECURITY WARNING] JWT_SECRET is missing or weak in .env. Using an ephemeral dev secret. Set a 64-char random JWT_SECRET in .env immediately.')
    return crypto.randomBytes(32).toString('hex')
  }
  return envSecret
}

export const JWT_SECRET = resolveJwtSecret()

function deriveDefaultAppBaseUrl(): string {
  if (process.env.APP_BASE_URL) return process.env.APP_BASE_URL.replace(/\/+$/, '')
  const kcbUrl = process.env.KCB_CALLBACK_URL || ''
  if (kcbUrl) {
    try {
      return new URL(kcbUrl).origin
    } catch {}
  }
  return `http://localhost:${PORT}`
}

export const APP_BASE_URL = deriveDefaultAppBaseUrl()

// KCB Buni API Configuration — read strictly from environment variables (zero hardcoded secrets)
export const KCB_CONFIG = {
  baseUrl: (process.env.KCB_BASE_URL || 'https://uat.buni.kcbgroup.com').replace(/\/+$/, ''),
  consumerKey: (process.env.KCB_CONSUMER_KEY || '').trim(),
  consumerSecret: (process.env.KCB_CONSUMER_SECRET || '').trim(),
  defaultRouteCode: (process.env.KCB_DEFAULT_ROUTE_CODE || process.env.defaultRouteCode || '207').trim(),
  callbackUrl: (process.env.KCB_CALLBACK_URL || `${APP_BASE_URL}/api/kcb/callback`).trim(),
  webhookSecret: (process.env.KCB_WEBHOOK_SECRET || process.env.WEBHOOKSECRET || '').trim(),
  strictCallbackAuth: String(process.env.KCB_CALLBACK_STRICT || 'false').toLowerCase() === 'true'
}

// Fail fast in production if critical payment secrets are missing or UAT endpoint is left on by mistake
if (IS_PRODUCTION) {
  if (!KCB_CONFIG.consumerKey || !KCB_CONFIG.consumerSecret) {
    throw new Error('CRITICAL: KCB_CONSUMER_KEY and KCB_CONSUMER_SECRET must be configured in production.')
  }
  if (
    KCB_CONFIG.baseUrl.includes('uat.buni.kcbgroup.com') &&
    String(process.env.ALLOW_KCB_UAT_IN_PROD || 'false').toLowerCase() !== 'true'
  ) {
    console.warn('[SECURITY WARNING] Running in NODE_ENV=production with KCB UAT base URL. Set KCB_BASE_URL to production or set ALLOW_KCB_UAT_IN_PROD=true if intentional.')
  }
}

// MobileSasa SMS Gateway Configuration
export const MOBILESASA_CONFIG = {
  baseUrl: (process.env.MOBILESASA_BASE_URL || 'https://api.mobilesasa.com').replace(/\/+$/, ''),
  token: (process.env.MOBILESASA_TOKEN || '').trim(),
  senderId: (process.env.MOBILESASA_SENDER_ID || 'MOBILESASA').trim(),
  callbackUrl: (process.env.MOBILESASA_CALLBACK_URL || '').trim(),
  webhookSecret: (process.env.MOBILESASA_WEBHOOK_SECRET || '').trim()
}

// Allowed CORS Origins (comma-separated in CORS_ORIGINS + APP_BASE_URL + Firebase App Hosting origins + local dev)
const DEFAULT_HOSTED_ORIGINS = [
  'https://lapis-suites--lapis-suites-gataka.us-east4.hosted.app'
]

function normalizeOrigin(raw: string): string {
  const cleaned = raw.trim().replace(/^["']|["']$/g, '').replace(/\/+$/, '')
  if (!cleaned) return ''
  try {
    return new URL(cleaned).origin
  } catch {
    return cleaned
  }
}

function resolveAllowedOrigins(): string[] {
  const origins = new Set<string>()
  const fromEnv = (process.env.CORS_ORIGINS || '')
    .split(',')
    .map(normalizeOrigin)
    .filter(Boolean)
  for (const o of fromEnv) origins.add(o)
  if (APP_BASE_URL) {
    const normBase = normalizeOrigin(APP_BASE_URL)
    if (normBase) origins.add(normBase)
  }
  if (process.env.FIREBASE_APP_HOSTING_URL) {
    const normHosted = normalizeOrigin(process.env.FIREBASE_APP_HOSTING_URL)
    if (normHosted) origins.add(normHosted)
  }
  for (const hosted of DEFAULT_HOSTED_ORIGINS) {
    origins.add(normalizeOrigin(hosted))
  }
  if (!IS_PRODUCTION) {
    origins.add('http://localhost:5173')
    origins.add('http://127.0.0.1:5173')
    origins.add(`http://localhost:${PORT}`)
    origins.add(`http://127.0.0.1:${PORT}`)
  }
  return Array.from(origins)
}

export const ALLOWED_CORS_ORIGINS = resolveAllowedOrigins()

// Strict 2-Admin Authorization Policy (admin emails & OTP phones are managed exclusively in Settings / MongoDB)
export const MAX_ADMIN_ACCOUNTS = 2
export const ALLOWED_ADMIN_EMAIL_KEYWORDS = ['musigah', 'stallone', 'odhiambo', 'lapissuites'] as const

export function isAllowedAdminEmail(email: string): boolean {
  const normalized = String(email || '').trim().toLowerCase()
  if (!normalized || !normalized.includes('@')) return false
  return ALLOWED_ADMIN_EMAIL_KEYWORDS.some((kw) => normalized.includes(kw))
}

export function generateHexObjectId(): string {
  const timestamp = Math.floor(Date.now() / 1000).toString(16).padStart(8, '0')
  const randomChars = crypto.randomBytes(8).toString('hex')
  return `${timestamp}${randomChars}`
}

export function getClientIp(req: Request): string {
  // With Express `trust proxy` enabled, `req.ip` safely resolves the proxy-verified client IP
  if (req.ip) return req.ip.replace(/^::ffff:/, '')
  return (req.socket.remoteAddress || '127.0.0.1').replace(/^::ffff:/, '')
}

export function normalizeKenyanPhone(phone: string): string {
  let cleaned = String(phone || '').replace(/[\s\-\(\)\+]/g, '')
  if (cleaned.startsWith('0')) {
    cleaned = '254' + cleaned.substring(1)
  } else if (cleaned.startsWith('7') || cleaned.startsWith('1')) {
    cleaned = '254' + cleaned
  }
  return cleaned
}

export function maskKenyanPhone(phone: string): string {
  const normalized = normalizeKenyanPhone(phone)
  if (!normalized || normalized.length < 7) return '***'
  const lastThree = normalized.slice(-3)
  if (normalized.startsWith('254') && normalized.length >= 12) {
    return `+254 ${normalized.slice(3, 5)}* *** ${lastThree}`
  }
  return `${normalized.slice(0, 3)}****${lastThree}`
}
