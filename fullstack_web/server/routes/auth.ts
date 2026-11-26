import crypto from 'crypto'
import { Router, Request, Response } from 'express'
import jwt from 'jsonwebtoken'
import bcrypt from 'bcryptjs'
import { getDb, isDbConnected } from '../db'
import {
  JWT_SECRET,
  MAX_ADMIN_ACCOUNTS,
  generateHexObjectId,
  isAllowedAdminEmail,
  normalizeKenyanPhone,
  maskKenyanPhone
} from '../config'
import { getRentDueDay } from '../services/settings'
import { authenticateToken, requireRole, AuthRequest, AuthUserPayload } from '../middleware/auth'
import { createRateLimiter } from '../middleware/rateLimiter'
import { logServerEvent } from '../middleware/logger'
import { sendSms } from '../services/sms'
import { logAuditEvent } from '../services/audit'

const OTP_TTL_MS = 10 * 60 * 1000 // 10 minutes
const OTP_MAX_ATTEMPTS = 5
const SESSION_TOKEN_TTL = '7d'

function generateOtpCode(): string {
  return crypto.randomInt(100000, 1000000).toString()
}

function hashOtp(code: string): string {
  return crypto.createHash('sha256').update(`${code}:${JWT_SECRET}`).digest('hex')
}

function computeNextPaymentDueDate(dueDay: number = 5): string {
  const now = new Date()
  const target = new Date(now.getFullYear(), now.getMonth() + 1, dueDay)
  const yyyy = target.getFullYear()
  const mm = String(target.getMonth() + 1).padStart(2, '0')
  const dd = String(dueDay).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

async function resolveUserPhone(db: any, user: any): Promise<string> {
  if (user?.phone) {
    const cleaned = normalizeKenyanPhone(user.phone)
    if (/^254[17]\d{8}$/.test(cleaned)) return cleaned
  }

  // Admin phones are managed strictly in Settings (MongoDB users collection)
  if (user?.role === 'landlord') {
    return ''
  }

  const cleanEmail = String(user?.email || '').trim().toLowerCase()
  const tenantDoc = await db.collection('tenants').findOne({
    $or: [
      ...(cleanEmail ? [{ email: cleanEmail }] : []),
      ...(user?.tenantId ? [{ id: user.tenantId }] : []),
      ...(user?.id ? [{ id: user.id }] : [])
    ]
  })

  if (tenantDoc?.phone) {
    const cleaned = normalizeKenyanPhone(tenantDoc.phone)
    if (/^254[17]\d{8}$/.test(cleaned)) return cleaned
  }

  return ''
}

async function verifyAdminPolicy(db: any, user: any): Promise<{ ok: boolean; error?: string }> {
  if (!isAllowedAdminEmail(user.email)) {
    logServerEvent('SECURITY', `Blocked unauthorized admin login attempt: ${user.email}`)
    return {
      ok: false,
      error: 'Unauthorized administrator account. Admin email must belong to an authorized Lapis Suites administrator.'
    }
  }

  const validAdmins = await db.collection('users')
    .find({ role: 'landlord' })
    .sort({ createdAt: 1, _id: 1 })
    .toArray()

  const allowedAdmins = validAdmins
    .filter((u: any) => isAllowedAdminEmail(u.email))
    .slice(0, MAX_ADMIN_ACCOUNTS)

  const isWithinLimit = allowedAdmins.some((u: any) => u.email.toLowerCase() === user.email.toLowerCase())
  if (!isWithinLimit) {
    logServerEvent('SECURITY', `Blocked admin exceeding 2-admin limit: ${user.email}`)
    return {
      ok: false,
      error: `Administrator limit reached (maximum ${MAX_ADMIN_ACCOUNTS} active admin accounts allowed).`
    }
  }

  return { ok: true }
}

const router = Router()
const otpRateLimiter = createRateLimiter(8, 60 * 1000)
const loginRateLimiter = createRateLimiter(10, 15 * 60 * 1000, {
  keyGenerator: (req, ip) => {
    const email = String(req.body?.email || '').trim().toLowerCase()
    return `login:${ip}:${email || 'anon'}`
  },
  message: 'Too many sign-in attempts. Please wait 15 minutes before trying again.'
})

// POST /api/auth/login
// Tenants sign in directly; Admins (landlord) MUST complete 6-digit SMS OTP verification.
router.post('/login', loginRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const { email, password } = req.body
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required.' })
    }

    const cleanEmail = String(email).trim().toLowerCase()
    const user = await db.collection('users').findOne({ email: cleanEmail })

    if (!user) {
      logServerEvent('AUTH', `Failed login attempt: user not found (${cleanEmail})`)
      return res.status(401).json({ error: 'Invalid credentials. User does not exist.' })
    }

    const passwordMatch = bcrypt.compareSync(password, user.passwordHash)
    if (!passwordMatch) {
      // If a landlord pre-added this tenant and the tenant hasn't set their own secure password yet,
      // automatically send an SMS OTP so they can verify their phone and set a secure password!
      if (user.role === 'tenant' && user.accountClaimed === false) {
        const tenantPhone = await resolveUserPhone(db, user)
        if (tenantPhone) {
          const otpCode = generateOtpCode()
          const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()
          const smsRes = await sendSms({
            phone: tenantPhone,
            message: `Lapis Suites Account Setup OTP: ${otpCode}. Enter this code to confirm your identity and set your secure password. Valid 10 mins.`,
            purpose: 'password_reset_otp',
            recipientEmail: cleanEmail,
            userId: user.id
          })
          if (smsRes.ok) {
            await db.collection('users').updateOne(
              { id: user.id },
              {
                $set: {
                  verificationCodeHash: hashOtp(otpCode),
                  verificationCodeExpiresAt: expiresAt,
                  verificationCodeAttempts: 0,
                  updatedAt: new Date().toISOString()
                }
              }
            )
            logServerEvent('AUTH', `Unclaimed resident ${cleanEmail} attempted sign-in; dispatched setup OTP via SMS`)
            return res.json({
              ok: true,
              requiresAccountSetup: true,
              email: cleanEmail,
              expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
              message: 'Your resident profile was added by management. Enter the 6-digit SMS OTP sent to your phone to create a secure password.'
            })
          }
        }
      }

      logServerEvent('AUTH', `Failed login attempt: incorrect password for ${cleanEmail}`)
      return res.status(401).json({ error: 'Invalid credentials. Incorrect password.' })
    }

    // ADMIN 2FA FLOW: Enforce 2-admin policy + send mandatory SMS OTP to admin phone
    if (user.role === 'landlord') {
      const policy = await verifyAdminPolicy(db, user)
      if (!policy.ok) {
        return res.status(403).json({ error: policy.error })
      }

      const adminPhone = await resolveUserPhone(db, user)
      if (!adminPhone) {
        // First-time bootstrap: if no OTP phone has been configured in Settings yet for this admin,
        // allow sign-in directly so the admin can configure their OTP phone inside Settings.
        // Once set in Settings, EVERY admin login enforces mandatory 6-digit SMS OTP.
        logServerEvent('AUTH', `Admin ${cleanEmail} has no OTP phone configured in Settings yet; allowing bootstrap sign-in to Settings.`)
        const bootstrapPayload: AuthUserPayload = {
          userId: user.id,
          email: user.email,
          name: user.name,
          role: 'landlord',
          phone: '',
          tenantId: null,
          unitNumber: '',
          avatarInitials: user.avatarInitials || 'AD',
          tv: Number(user.tokenVersion || 0)
        }
        const token = jwt.sign(bootstrapPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
        return res.json({
          ok: true,
          token,
          user: bootstrapPayload,
          needsAdminPhoneSetup: true
        })
      }

      const otpCode = generateOtpCode()
      const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()
      const smsMessage = `Lapis Suites Admin Login OTP: ${otpCode}. Valid for 10 minutes. Do not share this code.`

      const smsResult = await sendSms({
        phone: adminPhone,
        message: smsMessage,
        purpose: 'admin_login_otp',
        recipientEmail: cleanEmail,
        userId: user.id
      })

      if (!smsResult.ok) {
        logServerEvent('AUTH', `Admin login OTP SMS dispatch failed for ${cleanEmail}: ${smsResult.error}`)
        return res.status(502).json({
          error: smsResult.error || 'Failed to dispatch admin login OTP via SMS. Please check MobileSasa configuration.'
        })
      }

      await db.collection('users').updateOne(
        { id: user.id },
        {
          $set: {
            phone: adminPhone,
            loginOtpHash: hashOtp(otpCode),
            loginOtpExpiresAt: expiresAt,
            loginOtpAttempts: 0,
            loginOtpTrackingId: smsResult.trackingId,
            updatedAt: new Date().toISOString()
          }
        }
      )

      const challengeToken = jwt.sign(
        {
          purpose: 'admin_login_otp',
          userId: user.id,
          email: cleanEmail
        },
        JWT_SECRET,
        { expiresIn: '10m' }
      )

      const maskedPhone = maskKenyanPhone(adminPhone)
      logServerEvent('AUTH', `Admin 2FA OTP dispatched to ${maskedPhone} for ${cleanEmail} [trackingId=${smsResult.trackingId}]`)

      return res.json({
        ok: true,
        requiresOtp: true,
        purpose: 'admin_login',
        challengeToken,
        email: cleanEmail,
        maskedPhone,
        expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
        message: `A 6-digit verification code has been sent via SMS to ${maskedPhone}.`
      })
    }

    // TENANT LOGIN FLOW — strict email/tenantId isolation (never match by phone or unitNumber, never mutate leases/transactions)
    let unitNumber = ''
    let tenantId: string | null = user.tenantId || null
    let tenantDoc = await db.collection('tenants').findOne({ email: cleanEmail })
    if (!tenantDoc && user.tenantId) {
      const byId = await db.collection('tenants').findOne({ id: user.tenantId })
      if (byId && (!byId.email || byId.email.toLowerCase() === cleanEmail)) {
        tenantDoc = byId
      }
    }

    if (tenantDoc) {
      tenantId = tenantDoc.id
      const activeLeases = await db.collection('leases')
        .find({
          tenantId: tenantDoc.id,
          status: { $in: ['active', 'pending_deposit'] }
        })
        .sort({ startDate: 1, createdAt: 1 })
        .toArray()

      const primaryLease = activeLeases[0] || null
      unitNumber = primaryLease?.unitNumber || tenantDoc.currentUnitNumber || ''
      const activeUnitNumbers = activeLeases.map((l: any) => l.unitNumber).filter(Boolean)

      await db.collection('tenants').updateOne(
        { id: tenantDoc.id },
        {
          $set: {
            currentUnitId: primaryLease ? primaryLease.unitId : null,
            currentUnitNumber: unitNumber,
            currentLeaseId: primaryLease ? primaryLease.id : null,
            unitNumbers: activeUnitNumbers
          }
        }
      )
      await db.collection('users').updateOne(
        { id: user.id },
        {
          $set: {
            unitNumber,
            tenantId: tenantDoc.id,
            ...(tenantDoc.phone && !user.phone ? { phone: tenantDoc.phone } : {})
          }
        }
      )
    } else {
      tenantId = null
      unitNumber = ''
    }

    const tokenPayload: AuthUserPayload = {
      userId: user.id,
      email: user.email,
      name: user.name,
      role: 'tenant',
      phone: user.phone || tenantDoc?.phone || '',
      tenantId,
      unitNumber,
      avatarInitials: user.avatarInitials || (user.name ? user.name.split(' ').map((n: string) => n[0]).join('').slice(0, 2).toUpperCase() : 'US'),
      tv: Number(user.tokenVersion || 0)
    }

    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
    logServerEvent('AUTH', `Successful login: ${user.name} <${user.email}> (${user.role})`)

    res.json({
      ok: true,
      token,
      user: tokenPayload
    })
  } catch (err: any) {
    logServerEvent('AUTH', `Login error: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/verify-login-otp
// Completes Admin 2FA login after validating the 6-digit SMS OTP
router.post('/verify-login-otp', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { challengeToken, code } = req.body

    if (!challengeToken || !code) {
      return res.status(400).json({ error: 'Verification session and 6-digit OTP code are required.' })
    }

    let decoded: any
    try {
      decoded = jwt.verify(String(challengeToken), JWT_SECRET)
    } catch {
      return res.status(401).json({ error: 'Login verification session expired. Please sign in again.' })
    }

    if (decoded.purpose !== 'admin_login_otp' || !decoded.userId) {
      return res.status(401).json({ error: 'Invalid verification session.' })
    }

    const user = await db.collection('users').findOne({ id: decoded.userId, role: 'landlord' })
    if (!user) {
      return res.status(404).json({ error: 'Administrator account not found.' })
    }

    const policy = await verifyAdminPolicy(db, user)
    if (!policy.ok) {
      return res.status(403).json({ error: policy.error })
    }

    if (!user.loginOtpHash || !user.loginOtpExpiresAt) {
      return res.status(400).json({ error: 'No active login OTP found. Please sign in again.' })
    }

    if (new Date(user.loginOtpExpiresAt).getTime() < Date.now()) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new verification code.' })
    }

    const attempts = Number(user.loginOtpAttempts || 0)
    if (attempts >= OTP_MAX_ATTEMPTS) {
      return res.status(429).json({ error: 'Maximum verification attempts exceeded. Please request a new code.' })
    }

    const cleanCode = String(code).replace(/\D/g, '').trim()
    if (cleanCode.length !== 6 || hashOtp(cleanCode) !== user.loginOtpHash) {
      await db.collection('users').updateOne(
        { id: user.id },
        { $inc: { loginOtpAttempts: 1 } }
      )
      const remaining = Math.max(0, OTP_MAX_ATTEMPTS - (attempts + 1))
      logServerEvent('AUTH', `Invalid admin login OTP attempt for ${user.email} (${remaining} remaining)`)
      return res.status(400).json({
        error: remaining > 0
          ? `Invalid OTP code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`
          : 'Invalid OTP code. Maximum attempts reached; please request a new code.'
      })
    }

    // Clear OTP state once consumed
    await db.collection('users').updateOne(
      { id: user.id },
      {
        $unset: {
          loginOtpHash: '',
          loginOtpExpiresAt: '',
          loginOtpAttempts: '',
          loginOtpTrackingId: ''
        },
        $set: { lastLoginAt: new Date().toISOString() }
      }
    )

    const tokenPayload: AuthUserPayload = {
      userId: user.id,
      email: user.email,
      name: user.name,
      role: 'landlord',
      phone: user.phone || '',
      tenantId: null,
      unitNumber: '',
      avatarInitials: user.avatarInitials || (user.name ? user.name.split(' ').map((n: string) => n[0]).join('').slice(0, 2).toUpperCase() : 'AD'),
      tv: Number(user.tokenVersion || 0)
    }

    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
    logServerEvent('AUTH', `Admin 2FA verified & signed in: ${user.name} <${user.email}>`)

    res.json({
      ok: true,
      token,
      user: tokenPayload
    })
  } catch (err: any) {
    logServerEvent('AUTH', `Admin OTP verification error: ${err.message}`)
    res.status(500).json({ error: 'Failed to verify login OTP.' })
  }
})

// POST /api/auth/resend-login-otp
router.post('/resend-login-otp', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { challengeToken } = req.body

    if (!challengeToken) {
      return res.status(400).json({ error: 'Verification session is required.' })
    }

    let decoded: any
    try {
      decoded = jwt.verify(String(challengeToken), JWT_SECRET)
    } catch {
      return res.status(401).json({ error: 'Login verification session expired. Please sign in again.' })
    }

    if (decoded.purpose !== 'admin_login_otp' || !decoded.userId) {
      return res.status(401).json({ error: 'Invalid verification session.' })
    }

    const user = await db.collection('users').findOne({ id: decoded.userId, role: 'landlord' })
    if (!user) {
      return res.status(404).json({ error: 'Administrator account not found.' })
    }

    const adminPhone = await resolveUserPhone(db, user)
    if (!adminPhone) {
      return res.status(400).json({ error: 'No admin phone number configured for SMS OTP.' })
    }

    const otpCode = generateOtpCode()
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()
    const smsResult = await sendSms({
      phone: adminPhone,
      message: `Lapis Suites Admin Login OTP: ${otpCode}. Valid for 10 minutes. Do not share this code.`,
      purpose: 'admin_login_otp',
      recipientEmail: user.email,
      userId: user.id
    })

    if (!smsResult.ok) {
      return res.status(502).json({ error: smsResult.error || 'Failed to resend OTP via SMS.' })
    }

    await db.collection('users').updateOne(
      { id: user.id },
      {
        $set: {
          loginOtpHash: hashOtp(otpCode),
          loginOtpExpiresAt: expiresAt,
          loginOtpAttempts: 0,
          loginOtpTrackingId: smsResult.trackingId,
          updatedAt: new Date().toISOString()
        }
      }
    )

    const refreshedChallenge = jwt.sign(
      { purpose: 'admin_login_otp', userId: user.id, email: user.email },
      JWT_SECRET,
      { expiresIn: '10m' }
    )

    const maskedPhone = maskKenyanPhone(adminPhone)
    logServerEvent('AUTH', `Resent Admin 2FA OTP to ${maskedPhone} for ${user.email}`)
    res.json({
      ok: true,
      challengeToken: refreshedChallenge,
      maskedPhone,
      expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
      message: `A new 6-digit code has been sent via SMS to ${maskedPhone}.`
    })
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to resend login OTP.' })
  }
})

// POST /api/auth/register/request-otp
// Supports BOTH:
// 1. Existing landlord-added tenant claiming their account (sets a secure password after SMS OTP)
// 2. Brand-new resident creating an account (must confirm with SMS OTP before account activation)
router.post('/register/request-otp', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { email, name, phone, password } = req.body

    if (!email || !password) {
      return res.status(400).json({ error: 'Email address and a secure password are required.' })
    }
    if (String(password).length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters long.' })
    }

    const cleanEmail = String(email).trim().toLowerCase()
    const existingUser = await db.collection('users').findOne({ email: cleanEmail })
    const existingTenant = await db.collection('tenants').findOne({ email: cleanEmail })

    if (existingUser?.role === 'landlord') {
      return res.status(403).json({ error: 'This email belongs to an administrator account. Please sign in directly.' })
    }

    // If resident already claimed their account, still allow OTP-based claim only if unclaimed
    const isClaimFlow = Boolean(existingUser || existingTenant)
    if (existingUser && existingUser.accountClaimed === true) {
      return res.status(409).json({
        error: 'An account with this email is already active. Please sign in or use Forgot Password.'
      })
    }

    if (!isClaimFlow && (!name || !String(name).trim())) {
      return res.status(400).json({ error: 'Full legal name is required for new resident registration.' })
    }

    // Resolve phone to send OTP to: for pre-existing tenant, prefer their registered phone (or verify entered phone)
    const rawEnteredPhone = phone ? normalizeKenyanPhone(String(phone)) : ''
    const existingPhone = existingTenant?.phone
      ? normalizeKenyanPhone(existingTenant.phone)
      : (existingUser?.phone ? normalizeKenyanPhone(existingUser.phone) : '')

    let targetPhone = ''
    if (isClaimFlow && existingPhone && /^254[17]\d{8}$/.test(existingPhone)) {
      if (rawEnteredPhone && rawEnteredPhone.slice(-9) !== existingPhone.slice(-9)) {
        return res.status(403).json({
          error: 'The phone number entered does not match the mobile number registered on your resident profile.'
        })
      }
      targetPhone = existingPhone
    } else {
      targetPhone = rawEnteredPhone
    }

    if (!targetPhone || !/^254[17]\d{8}$/.test(targetPhone)) {
      return res.status(400).json({ error: 'Please enter a valid 9-digit Kenyan mobile number starting with 7 or 1.' })
    }

    const otpCode = generateOtpCode()
    const challengeId = generateHexObjectId()
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()
    const resolvedName = String(name || existingTenant?.name || existingUser?.name || 'Resident').trim()

    const smsMsg = isClaimFlow
      ? `Lapis Suites Account Activation OTP: ${otpCode}. Enter this code to confirm your identity and activate your secure password. Valid 10 mins.`
      : `Lapis Suites Registration OTP: ${otpCode}. Enter this code to verify your phone and complete account creation. Valid 10 mins.`

    const smsRes = await sendSms({
      phone: targetPhone,
      message: smsMsg,
      purpose: 'password_reset_otp',
      recipientEmail: cleanEmail,
      userId: existingUser?.id || existingTenant?.id
    })

    if (!smsRes.ok) {
      return res.status(502).json({ error: smsRes.error || 'Failed to dispatch SMS verification code.' })
    }

    await db.collection('register_otps').insertOne({
      challengeId,
      mode: isClaimFlow ? 'claim' : 'new',
      email: cleanEmail,
      name: resolvedName,
      phone: targetPhone,
      passwordHash: bcrypt.hashSync(String(password), 10),
      otpHash: hashOtp(otpCode),
      attempts: 0,
      used: false,
      expiresAt,
      createdAt: new Date().toISOString()
    })

    const challengeToken = jwt.sign(
      { purpose: 'register_otp', challengeId, email: cleanEmail },
      JWT_SECRET,
      { expiresIn: '10m' }
    )

    logServerEvent('AUTH', `Dispatched ${isClaimFlow ? 'account-claim' : 'registration'} OTP via SMS for ${cleanEmail}`)
    res.json({
      ok: true,
      mode: isClaimFlow ? 'claim' : 'new',
      challengeToken,
      email: cleanEmail,
      expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
      message: isClaimFlow
        ? 'We found your resident profile! Enter the 6-digit SMS OTP sent to your phone to activate your secure password.'
        : 'A 6-digit verification code has been sent via SMS to your mobile phone.'
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/register/verify-otp
// Verifies the 6-digit SMS OTP and completes either new resident creation or existing tenant account claim
router.post('/register/verify-otp', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { challengeToken, code } = req.body
    if (!challengeToken || !code) {
      return res.status(400).json({ error: 'Verification session and 6-digit OTP code are required.' })
    }

    let decoded: any
    try {
      decoded = jwt.verify(String(challengeToken), JWT_SECRET)
    } catch {
      return res.status(401).json({ error: 'Verification session expired. Please request a new OTP.' })
    }

    if (decoded.purpose !== 'register_otp' || !decoded.challengeId) {
      return res.status(401).json({ error: 'Invalid verification session.' })
    }

    const regDoc = await db.collection('register_otps').findOne({ challengeId: decoded.challengeId })
    if (!regDoc || regDoc.used) {
      return res.status(400).json({ error: 'This verification code has already been used or is invalid.' })
    }
    if (new Date(regDoc.expiresAt).getTime() < Date.now()) {
      return res.status(400).json({ error: 'Verification code expired. Please request a new code.' })
    }
    if (Number(regDoc.attempts || 0) >= OTP_MAX_ATTEMPTS) {
      return res.status(429).json({ error: 'Too many invalid attempts. Please request a new verification code.' })
    }

    const cleanCode = String(code).replace(/\D/g, '').trim()
    if (cleanCode.length !== 6 || hashOtp(cleanCode) !== regDoc.otpHash) {
      await db.collection('register_otps').updateOne({ challengeId: regDoc.challengeId }, { $inc: { attempts: 1 } })
      return res.status(400).json({ error: 'Invalid 6-digit verification code. Please check your SMS and try again.' })
    }

    const nowIso = new Date().toISOString()
    await db.collection('register_otps').updateOne(
      { challengeId: regDoc.challengeId },
      { $set: { used: true, verifiedAt: nowIso } }
    )

    const cleanEmail = regDoc.email
    const trimmedName = regDoc.name
    const cleanPhone = regDoc.phone
    const initials = trimmedName.split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase() || 'TN'
    const configuredDueDay = await getRentDueDay()

    // Locate or create tenant profile STRICTLY by email (NEVER match another resident by shared phone!)
    let tenantDoc = await db.collection('tenants').findOne({ email: cleanEmail })

    let assignedUnitNumber = tenantDoc?.currentUnitNumber || ''
    if (tenantDoc) {
      if (!assignedUnitNumber) {
        const lease = await db.collection('leases').findOne(
          {
            tenantId: tenantDoc.id,
            status: { $in: ['active', 'pending_deposit'] }
          },
          { sort: { startDate: 1, createdAt: 1 } }
        )
        if (lease?.unitNumber) {
          assignedUnitNumber = lease.unitNumber
          await db.collection('tenants').updateOne(
            { id: tenantDoc.id },
            { $set: { currentUnitId: lease.unitId, currentUnitNumber: lease.unitNumber, currentLeaseId: lease.id } }
          )
        }
      }
      if (!tenantDoc.phone && cleanPhone) {
        await db.collection('tenants').updateOne({ id: tenantDoc.id }, { $set: { phone: cleanPhone } })
      }
    } else {
      const newTenantId = generateHexObjectId()
      tenantDoc = {
        id: newTenantId,
        name: trimmedName,
        email: cleanEmail,
        phone: cleanPhone,
        nationalId: 'ID-PENDING',
        currentUnitId: null,
        currentUnitNumber: '',
        currentLeaseId: null,
        balance: 0,
        arrearsBalance: 0,
        accountCredit: 0,
        nextPaymentDueDate: computeNextPaymentDueDate(configuredDueDay),
        status: 'active',
        moveInDate: nowIso.slice(0, 10),
        avatarInitials: initials,
        createdAt: nowIso
      } as any
      await db.collection('tenants').insertOne(tenantDoc as any)
    }

    // Update existing user doc (claim) or insert new user doc
    const existingUser = await db.collection('users').findOne({ email: cleanEmail })
    let userId: string

    if (existingUser) {
      userId = existingUser.id
      await db.collection('users').updateOne(
        { id: existingUser.id },
        {
          $set: {
            passwordHash: regDoc.passwordHash,
            name: trimmedName || existingUser.name,
            phone: cleanPhone,
            role: 'tenant',
            accountClaimed: true,
            tenantId: tenantDoc!.id,
            unitNumber: assignedUnitNumber || existingUser.unitNumber || '',
            avatarInitials: existingUser.avatarInitials || initials,
            updatedAt: nowIso
          }
        }
      )
    } else {
      userId = tenantDoc!.id || generateHexObjectId()
      await db.collection('users').insertOne({
        id: userId,
        email: cleanEmail,
        passwordHash: regDoc.passwordHash,
        name: trimmedName,
        phone: cleanPhone,
        role: 'tenant',
        accountClaimed: true,
        tenantId: tenantDoc!.id,
        unitNumber: assignedUnitNumber || '',
        avatarInitials: initials,
        createdAt: nowIso
      })
    }

    const tokenPayload: AuthUserPayload = {
      userId,
      email: cleanEmail,
      name: trimmedName,
      role: 'tenant',
      phone: cleanPhone,
      tenantId: tenantDoc!.id,
      unitNumber: assignedUnitNumber || '',
      avatarInitials: initials
    }

    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
    logServerEvent('AUTH', `Verified SMS OTP and activated resident account: ${cleanEmail} (${regDoc.mode})`)

    res.status(201).json({
      ok: true,
      token,
      user: tokenPayload,
      tenant: tenantDoc
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/register (Legacy fallback kept secure — redirects clients to OTP flow)
// Strictly creates resident ('tenant') accounts only — never allows public admin creation.
router.post('/register', async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const { email, password, name, phone } = req.body
    if (!email || !password || !name) {
      return res.status(400).json({ error: 'Full name, email, and password are required.' })
    }

    if (String(password).length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters long.' })
    }

    const cleanEmail = String(email).trim().toLowerCase()
    const existingUser = await db.collection('users').findOne({ email: cleanEmail })
    if (existingUser) {
      return res.status(409).json({ error: 'An account with this email address already exists.' })
    }

    // Force tenant role on all public registrations
    const role: 'tenant' = 'tenant'
    const trimmedName = String(name).trim()
    const initials = trimmedName.split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase() || 'TN'
    const newUserId = generateHexObjectId()
    const passwordHash = bcrypt.hashSync(password, 10)
    const rawPhone = phone ? String(phone).trim() : ''
    const cleanPhone = rawPhone ? normalizeKenyanPhone(rawPhone) : ''

    let newTenantDoc: any = null
    let assignedUnitNumber = ''
    const existingTenant = await db.collection('tenants').findOne({ email: cleanEmail })

    if (existingTenant) {
      newTenantDoc = existingTenant
      assignedUnitNumber = existingTenant.currentUnitNumber || ''
      if (!assignedUnitNumber) {
        const lease = await db.collection('leases').findOne(
          {
            tenantId: existingTenant.id,
            status: { $in: ['active', 'pending_deposit'] }
          },
          { sort: { startDate: 1, createdAt: 1 } }
        )
        if (lease && lease.unitNumber) {
          assignedUnitNumber = lease.unitNumber
          await db.collection('tenants').updateOne(
            { id: existingTenant.id },
            { $set: { currentUnitId: lease.unitId, currentUnitNumber: lease.unitNumber, currentLeaseId: lease.id } }
          )
        }
      }
    } else {
      newTenantDoc = {
        id: newUserId,
        name: trimmedName,
        email: cleanEmail,
        phone: cleanPhone || rawPhone,
        nationalId: 'ID-PENDING',
        currentUnitId: null,
        currentUnitNumber: '',
        currentLeaseId: null,
        balance: 0,
        arrearsBalance: 0,
        accountCredit: 0,
        nextPaymentDueDate: computeNextPaymentDueDate(),
        status: 'active',
        moveInDate: new Date().toISOString().slice(0, 10),
        avatarInitials: initials,
        createdAt: new Date().toISOString()
      }
      await db.collection('tenants').insertOne(newTenantDoc)
    }

    const newUserDoc = {
      id: newUserId,
      email: cleanEmail,
      passwordHash,
      name: trimmedName,
      phone: cleanPhone || rawPhone || existingTenant?.phone || '',
      role,
      tenantId: newTenantDoc ? newTenantDoc.id : newUserId,
      unitNumber: assignedUnitNumber || '',
      avatarInitials: initials,
      createdAt: new Date().toISOString()
    }

    await db.collection('users').insertOne(newUserDoc)

    const tokenPayload: AuthUserPayload = {
      userId: newUserId,
      email: cleanEmail,
      name: trimmedName,
      role,
      phone: newUserDoc.phone,
      tenantId: newTenantDoc ? newTenantDoc.id : newUserId,
      unitNumber: assignedUnitNumber || '',
      avatarInitials: initials
    }

    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
    logServerEvent('AUTH', `Registered new resident: ${cleanEmail} (${trimmedName})`)
    res.status(201).json({ ok: true, token, user: tokenPayload, tenant: newTenantDoc })
  } catch (err: any) {
    logServerEvent('AUTH', `Registration error: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// GET /api/auth/me
router.get('/me', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    if (!req.user) return res.status(401).json({ error: 'Unauthorized' })
    if (!isDbConnected()) return res.json({ user: req.user })
    const db = getDb()

    const user = await db.collection('users').findOne({ id: req.user.userId }) ||
                 await db.collection('users').findOne({ email: (req.user.email || '').toLowerCase() })

    let unitNumber = user?.unitNumber || req.user.unitNumber || ''
    let tenantId = user?.tenantId || req.user.tenantId || null
    let phone = user?.phone || req.user.phone || ''

    if (req.user.role === 'tenant' || user?.role === 'tenant') {
      const cleanEmail = (req.user.email || user?.email || '').toLowerCase()
      let tenantDoc = cleanEmail ? await db.collection('tenants').findOne({ email: cleanEmail }) : null
      if (!tenantDoc && tenantId) {
        const byId = await db.collection('tenants').findOne({ id: tenantId })
        if (byId && (!byId.email || byId.email.toLowerCase() === cleanEmail)) {
          tenantDoc = byId
        }
      }

      if (tenantDoc) {
        tenantId = tenantDoc.id
        phone = phone || tenantDoc.phone || ''
        const activeLeases = await db.collection('leases')
          .find({
            tenantId: tenantDoc.id,
            status: { $in: ['active', 'pending_deposit'] }
          })
          .sort({ startDate: 1, createdAt: 1 })
          .toArray()
        const primaryLease = activeLeases[0] || null
        unitNumber = primaryLease?.unitNumber || tenantDoc.currentUnitNumber || ''
      } else {
        tenantId = null
        unitNumber = ''
      }
    } else if (user?.role === 'landlord') {
      phone = user.phone || ''
    }

    const payload: AuthUserPayload = {
      userId: user?.id || req.user.userId,
      email: user?.email || req.user.email,
      name: user?.name || req.user.name,
      role: user?.role || req.user.role,
      phone,
      tenantId: tenantId || req.user.tenantId || null,
      unitNumber: unitNumber || '',
      avatarInitials: user?.avatarInitials || req.user.avatarInitials || 'US',
      tv: Number(user?.tokenVersion || 0)
    }

    res.json({ user: payload })
  } catch (err: any) {
    res.json({ user: req.user })
  }
})

// POST /api/auth/refresh — Sliding 7-day session refresh for authenticated users
router.post('/refresh', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = await db.collection('users').findOne({ id: req.user!.userId })
    if (!user) {
      return res.status(401).json({ error: 'Account no longer exists. Please sign in again.' })
    }
    if (user.role === 'landlord') {
      const policy = await verifyAdminPolicy(db, user)
      if (!policy.ok) return res.status(403).json({ error: policy.error })
    }

    let tenantId: string | null = user.tenantId || null
    let unitNumber = user.unitNumber || ''
    let phone = user.phone || ''

    if (user.role === 'tenant') {
      const cleanEmail = String(user.email || '').trim().toLowerCase()
      const tenantDoc = cleanEmail ? await db.collection('tenants').findOne({ email: cleanEmail }) : null
      if (tenantDoc) {
        tenantId = tenantDoc.id
        phone = phone || tenantDoc.phone || ''
        const primaryLease = await db.collection('leases').findOne(
          { tenantId: tenantDoc.id, status: { $in: ['active', 'pending_deposit'] } },
          { sort: { startDate: 1, createdAt: 1 } }
        )
        unitNumber = primaryLease?.unitNumber || tenantDoc.currentUnitNumber || ''
      }
    }

    const tokenPayload: AuthUserPayload = {
      userId: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      phone,
      tenantId,
      unitNumber,
      avatarInitials: user.avatarInitials || 'US',
      tv: Number(user.tokenVersion || 0)
    }

    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
    res.json({ ok: true, token, user: tokenPayload })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/logout-all — Revokes all active sessions across all devices by bumping tokenVersion
router.post('/logout-all', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    await db.collection('users').updateOne(
      { id: req.user!.userId },
      { $inc: { tokenVersion: 1 }, $set: { updatedAt: new Date().toISOString() } }
    )
    logServerEvent('AUTH', `Revoked all sessions for ${req.user!.email}`)
    await logAuditEvent({
      actor: req.user,
      action: 'auth.logout_all',
      entityType: 'auth',
      entityId: req.user!.userId,
      summary: `${req.user!.name} signed out of all devices`
    })
    res.json({ ok: true, message: 'All active sessions have been signed out.' })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/change-password — Authenticated password change (requires currentPassword; bumps tokenVersion & returns fresh JWT)
router.post('/change-password', async (req: Request, res: Response, next) => {
  // If client sends resetToken or code without Authorization header, pass through to legacy reset flow below
  if (!req.headers['authorization'] && (req.body?.resetToken || req.body?.code)) {
    return next()
  }
  return authenticateToken(req as AuthRequest, res, async () => {
    try {
      const authReq = req as AuthRequest
      const db = getDb()
      const currentPassword = String(req.body?.currentPassword || '')
      const newPassword = String(req.body?.newPassword || req.body?.password || '')
      const confirmPassword = String(req.body?.confirmPassword ?? newPassword)

      if (!currentPassword || !newPassword) {
        return res.status(400).json({ error: 'Current password and new password are required.' })
      }
      if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters long.' })
      }
      if (newPassword !== confirmPassword) {
        return res.status(400).json({ error: 'New passwords do not match.' })
      }
      if (currentPassword === newPassword) {
        return res.status(400).json({ error: 'New password must be different from your current password.' })
      }

      const user = await db.collection('users').findOne({ id: authReq.user!.userId })
      if (!user) {
        return res.status(404).json({ error: 'Account not found.' })
      }
      if (!bcrypt.compareSync(currentPassword, user.passwordHash)) {
        return res.status(400).json({ error: 'Current password is incorrect.' })
      }

      const nextTv = Number(user.tokenVersion || 0) + 1
      await db.collection('users').updateOne(
        { id: user.id },
        {
          $set: {
            passwordHash: bcrypt.hashSync(newPassword, 10),
            tokenVersion: nextTv,
            accountClaimed: true,
            updatedAt: new Date().toISOString()
          }
        }
      )

      const freshPayload: AuthUserPayload = {
        userId: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        phone: user.phone || authReq.user!.phone || '',
        tenantId: user.tenantId || authReq.user!.tenantId || null,
        unitNumber: user.unitNumber || authReq.user!.unitNumber || '',
        avatarInitials: user.avatarInitials || authReq.user!.avatarInitials || 'US',
        tv: nextTv
      }
      const token = jwt.sign(freshPayload, JWT_SECRET, { expiresIn: SESSION_TOKEN_TTL })
      logServerEvent('AUTH', `Changed password and rotated sessions for ${user.email}`)
      await logAuditEvent({
        actor: authReq.user,
        action: 'auth.change_password',
        entityType: 'auth',
        entityId: user.id,
        summary: `${user.name} changed account password (revoked prior sessions)`
      })
      res.json({ ok: true, token, user: freshPayload, message: 'Password updated successfully.' })
    } catch (err: any) {
      res.status(500).json({ error: err.message })
    }
  })
})

// PUT /api/auth/admin-phone
// Lets an authenticated administrator view/update their registered OTP phone number
router.put('/admin-phone', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const rawPhone = String(req.body?.phone || '').trim()
    const normalized = normalizeKenyanPhone(rawPhone)
    if (!/^254[17]\d{8}$/.test(normalized)) {
      return res.status(400).json({ error: 'Please provide a valid Kenyan mobile number (e.g. 0712345678 or +254712345678).' })
    }

    await db.collection('users').updateOne(
      { email: req.user!.email.toLowerCase(), role: 'landlord' },
      { $set: { phone: normalized, updatedAt: new Date().toISOString() } }
    )

    logServerEvent('AUTH', `Updated admin OTP phone for ${req.user!.email} -> ${maskKenyanPhone(normalized)}`)
    res.json({
      ok: true,
      phone: normalized,
      maskedPhone: maskKenyanPhone(normalized)
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/auth/forgot-password
// Generates a 6-digit OTP and dispatches it via MobileSasa SMS to the account's registered phone
router.all('/forgot-password', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const email = req.body?.email || req.query?.email
    if (!email) {
      return res.status(400).json({ error: 'Email address is required.' })
    }

    const cleanEmail = String(email).trim().toLowerCase()
    const user = await db.collection('users').findOne({ email: cleanEmail })
    if (!user) {
      logServerEvent('AUTH', `Password recovery requested for non-existent email: ${cleanEmail}`)
      return res.status(404).json({ error: 'No account found with this email address.' })
    }

    if (user.role === 'landlord') {
      const policy = await verifyAdminPolicy(db, user)
      if (!policy.ok) {
        return res.status(403).json({ error: policy.error })
      }
    }

    const recipientPhone = await resolveUserPhone(db, user)
    if (!recipientPhone) {
      logServerEvent('AUTH', `Password recovery failed: no phone linked to ${cleanEmail}`)
      return res.status(400).json({
        error: user.role === 'landlord'
          ? 'No phone number is configured for this admin account yet. Add the admin phone in Settings.'
          : 'No mobile phone number is linked to this account for SMS OTP delivery. Please contact property management.'
      })
    }

    const otpCode = generateOtpCode()
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()
    const smsMessage = `Lapis Suites Password Reset OTP: ${otpCode}. Valid for 10 minutes. Ignore if you did not request this.`

    const smsResult = await sendSms({
      phone: recipientPhone,
      message: smsMessage,
      purpose: 'password_reset_otp',
      recipientEmail: cleanEmail,
      userId: user.id
    })

    if (!smsResult.ok) {
      logServerEvent('AUTH', `Password reset SMS failed for ${cleanEmail}: ${smsResult.error}`)
      return res.status(502).json({
        error: smsResult.error || 'Unable to send SMS verification code. Please try again shortly.'
      })
    }

    await db.collection('users').updateOne(
      { id: user.id },
      {
        $set: {
          verificationCodeHash: hashOtp(otpCode),
          verificationCodeExpiresAt: expiresAt,
          verificationCodeAttempts: 0,
          verificationCodeTrackingId: smsResult.trackingId,
          updatedAt: new Date().toISOString()
        },
        $unset: {
          verificationCode: ''
        }
      }
    )

    const maskedPhone = maskKenyanPhone(recipientPhone)
    logServerEvent('AUTH', `PASSWORD RECOVERY: Dispatched 6-digit SMS OTP to ${maskedPhone} for ${user.email} [trackingId=${smsResult.trackingId}]`)

    res.json({
      ok: true,
      email: cleanEmail,
      maskedPhone,
      expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
      message: `A 6-digit verification code has been sent via SMS to ${maskedPhone}.`
    })
  } catch (err: any) {
    logServerEvent('AUTH', `Failed to generate verification code: ${err.message}`)
    res.status(500).json({ error: 'Failed to generate verification code.' })
  }
})

// POST /api/auth/verify-code
// Verifies the 6-digit SMS OTP for password recovery and returns a short-lived signed resetToken
router.all('/verify-code', otpRateLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const email = req.body?.email || req.query?.email
    const code = req.body?.code || req.query?.code

    if (!email || !code) {
      return res.status(400).json({ error: 'Email and 6-digit verification code are required.' })
    }

    const cleanEmail = String(email).trim().toLowerCase()
    const cleanCode = String(code).replace(/\D/g, '').trim()

    if (cleanCode.length !== 6) {
      return res.status(400).json({ error: 'Please enter the complete 6-digit verification code.' })
    }

    const user = await db.collection('users').findOne({ email: cleanEmail })
    if (!user) {
      return res.status(404).json({ error: 'User account not found.' })
    }

    if (!user.verificationCodeHash) {
      return res.status(400).json({ error: 'No active verification code found. Please request a new one.' })
    }

    if (user.verificationCodeExpiresAt && new Date(user.verificationCodeExpiresAt).getTime() < Date.now()) {
      logServerEvent('AUTH', `Verification code expired for ${cleanEmail}`)
      return res.status(400).json({ error: 'Verification code has expired. Please request a new code.' })
    }

    const attempts = Number(user.verificationCodeAttempts || 0)
    if (attempts >= OTP_MAX_ATTEMPTS) {
      return res.status(429).json({ error: 'Too many invalid attempts. Please request a new verification code.' })
    }

    if (hashOtp(cleanCode) !== user.verificationCodeHash) {
      await db.collection('users').updateOne(
        { id: user.id },
        { $inc: { verificationCodeAttempts: 1 } }
      )
      const remaining = Math.max(0, OTP_MAX_ATTEMPTS - (attempts + 1))
      logServerEvent('AUTH', `Invalid recovery OTP attempt for ${cleanEmail} (${remaining} remaining)`)
      return res.status(400).json({
        error: remaining > 0
          ? `Invalid verification code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`
          : 'Invalid verification code. Please request a new code.'
      })
    }

    const resetToken = jwt.sign(
      {
        purpose: 'password_reset',
        userId: user.id,
        email: cleanEmail,
        codeHash: user.verificationCodeHash
      },
      JWT_SECRET,
      { expiresIn: '10m' }
    )

    logServerEvent('AUTH', `Recovery OTP verified for ${cleanEmail}`)
    res.json({
      ok: true,
      email: cleanEmail,
      resetToken,
      message: 'Verification code confirmed. You may now set a new password.'
    })
  } catch (err: any) {
    logServerEvent('AUTH', `Failed to verify code: ${err.message}`)
    res.status(500).json({ error: 'Failed to verify code.' })
  }
})

// POST /api/auth/reset-password (and /api/auth/change-password)
// Requires a valid verified resetToken (or matching active OTP code), hashes password with bcrypt, and clears OTP
router.all(['/reset-password', '/change-password'], async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const email = req.body?.email || req.query?.email
    const resetToken = req.body?.resetToken || req.query?.resetToken
    const code = req.body?.code || req.query?.code
    const password = req.body?.password
    const confirmPassword = req.body?.confirmPassword

    if (!password || !confirmPassword) {
      return res.status(400).json({ error: 'New password and confirmation are required.' })
    }

    if (password !== confirmPassword) {
      return res.status(400).json({ error: 'Passwords do not match.' })
    }

    if (String(password).length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters long.' })
    }

    let cleanEmail = email ? String(email).trim().toLowerCase() : ''
    let verifiedUser: any = null

    if (resetToken) {
      let decoded: any
      try {
        decoded = jwt.verify(String(resetToken), JWT_SECRET)
      } catch {
        return res.status(401).json({ error: 'Reset session has expired. Please request a new verification code.' })
      }
      if (decoded.purpose !== 'password_reset' || !decoded.userId) {
        return res.status(401).json({ error: 'Invalid password reset token.' })
      }
      verifiedUser = await db.collection('users').findOne({ id: decoded.userId })
      if (!verifiedUser || !verifiedUser.verificationCodeHash || verifiedUser.verificationCodeHash !== decoded.codeHash) {
        return res.status(400).json({ error: 'This reset session has already been used or superseded. Please start again.' })
      }
      cleanEmail = verifiedUser.email
    } else if (cleanEmail && code) {
      verifiedUser = await db.collection('users').findOne({ email: cleanEmail })
      if (!verifiedUser) {
        return res.status(404).json({ error: 'User account not found.' })
      }
      const cleanCode = String(code).replace(/\D/g, '').trim()
      if (!verifiedUser.verificationCodeHash || hashOtp(cleanCode) !== verifiedUser.verificationCodeHash) {
        return res.status(400).json({ error: 'Invalid verification code.' })
      }
      if (verifiedUser.verificationCodeExpiresAt && new Date(verifiedUser.verificationCodeExpiresAt).getTime() < Date.now()) {
        return res.status(400).json({ error: 'Verification code has expired. Please request a new code.' })
      }
    } else {
      return res.status(400).json({ error: 'Verified reset token is required. Please verify your SMS OTP first.' })
    }

    const passwordHash = bcrypt.hashSync(password, 10)
    await db.collection('users').updateOne(
      { id: verifiedUser.id },
      {
        $inc: { tokenVersion: 1 },
        $set: {
          passwordHash,
          accountClaimed: true,
          updatedAt: new Date().toISOString()
        },
        $unset: {
          verificationCode: '',
          verificationCodeHash: '',
          verificationCodeExpiresAt: '',
          verificationCodeAttempts: '',
          verificationCodeTrackingId: ''
        }
      }
    )

    logServerEvent('AUTH', `PASSWORD RESET: Successfully updated password for ${verifiedUser.email}`)
    await logAuditEvent({
      actor: { userId: verifiedUser.id, email: verifiedUser.email, name: verifiedUser.name, role: verifiedUser.role },
      action: 'auth.reset_password',
      entityType: 'auth',
      entityId: verifiedUser.id,
      summary: `Password reset via SMS OTP for ${verifiedUser.email} (all prior sessions revoked)`
    })
    res.json({
      ok: true,
      email: cleanEmail,
      message: 'Password has been reset successfully. You may now sign in with your new credentials.'
    })
  } catch (err: any) {
    logServerEvent('AUTH', `Failed to reset password: ${err.message}`)
    res.status(500).json({ error: 'Failed to reset password.' })
  }
})

export default router
