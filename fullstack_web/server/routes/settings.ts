import { Router, Response } from 'express'
import bcrypt from 'bcryptjs'
import { getDb } from '../db'
import {
  MAX_ADMIN_ACCOUNTS,
  ALLOWED_ADMIN_EMAIL_KEYWORDS,
  generateHexObjectId,
  isAllowedAdminEmail,
  normalizeKenyanPhone
} from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { getAppSettings, getAuthorizedAdminsFromDb } from '../services/settings'

const router = Router()

// GET /api/settings
// Returns property details, billing/rentDueDay settings, and (for admins) the 2 authorized admin accounts
router.get('/settings', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const settings = await getAppSettings()
    const isLandlord = req.user?.role === 'landlord'
    const admins = isLandlord ? await getAuthorizedAdminsFromDb() : []

    res.json({
      settings,
      admins,
      adminPolicy: {
        maxAdmins: MAX_ADMIN_ACCOUNTS,
        allowedKeywords: ALLOWED_ADMIN_EMAIL_KEYWORDS
      }
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// PUT /api/settings (Landlord only)
// Persists property info, rentDueDay, billing rules, and up to 2 authorized admin accounts (email + OTP phone) in MongoDB
router.put('/settings', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { settings: incomingSettings, admins: incomingAdmins } = req.body || {}
    const nowIso = new Date().toISOString()

    // 1. Update Property & Billing Settings
    if (incomingSettings && typeof incomingSettings === 'object') {
      const dueDay = Number(incomingSettings.rentDueDay)
      if (incomingSettings.rentDueDay !== undefined && (!Number.isFinite(dueDay) || dueDay < 1 || dueDay > 28)) {
        return res.status(400).json({ error: 'Rent due day must be a day of the month between 1 and 28.' })
      }

      const updateFields: Record<string, any> = { updatedAt: nowIso }
      const allowedStringFields = [
        'propertyName',
        'address',
        'city',
        'managerName',
        'contactPhone',
        'contactEmail',
        'paybillNumber',
        'currency'
      ]
      for (const field of allowedStringFields) {
        if (incomingSettings[field] !== undefined) {
          updateFields[field] = String(incomingSettings[field]).trim()
        }
      }
      if (incomingSettings.totalFloors !== undefined) {
        updateFields.totalFloors = Math.max(1, Number(incomingSettings.totalFloors) || 1)
      }
      if (incomingSettings.rentDueDay !== undefined) {
        updateFields.rentDueDay = Math.floor(dueDay)
      }
      if (incomingSettings.gracePeriodDays !== undefined) {
        updateFields.gracePeriodDays = Math.max(0, Math.min(20, Math.floor(Number(incomingSettings.gracePeriodDays) || 0)))
      }
      if (incomingSettings.lateFeePercent !== undefined) {
        updateFields.lateFeePercent = Math.max(0, Math.min(50, Number(incomingSettings.lateFeePercent) || 0))
      }
      if (incomingSettings.autoReconciliationEnabled !== undefined) {
        updateFields.autoReconciliationEnabled = Boolean(incomingSettings.autoReconciliationEnabled)
      }

      await db.collection('settings').updateOne(
        { id: 'property_settings' },
        { $set: updateFields, $setOnInsert: { id: 'property_settings' } },
        { upsert: true }
      )
    }

    // 2. Update Authorized Admin Accounts (strictly max 2, email must match policy)
    if (Array.isArray(incomingAdmins)) {
      const cleanedAdmins = incomingAdmins
        .filter((a: any) => a && String(a.email || '').trim().length > 0)
        .slice(0, MAX_ADMIN_ACCOUNTS)

      if (cleanedAdmins.length === 0) {
        return res.status(400).json({ error: 'At least one authorized administrator account is required.' })
      }
      if (incomingAdmins.filter((a: any) => a && String(a.email || '').trim().length > 0).length > MAX_ADMIN_ACCOUNTS) {
        return res.status(400).json({ error: `Only ${MAX_ADMIN_ACCOUNTS} administrator accounts are allowed.` })
      }

      const seenEmails = new Set<string>()
      for (const a of cleanedAdmins) {
        const cleanEmail = String(a.email).trim().toLowerCase()
        if (!isAllowedAdminEmail(cleanEmail)) {
          return res.status(400).json({
            error: `Admin email "${cleanEmail}" is not permitted. Admin emails must include one of: ${ALLOWED_ADMIN_EMAIL_KEYWORDS.join(', ')}.`
          })
        }
        if (seenEmails.has(cleanEmail)) {
          return res.status(400).json({ error: `Duplicate administrator email: ${cleanEmail}` })
        }
        seenEmails.add(cleanEmail)

        const rawPhone = String(a.phone || '').trim()
        if (rawPhone) {
          const normPhone = normalizeKenyanPhone(rawPhone)
          if (!/^254[17]\d{8}$/.test(normPhone)) {
            return res.status(400).json({
              error: `Invalid Kenyan mobile number for ${cleanEmail}. Use 07..., 01..., or +2547... format.`
            })
          }
        }
      }

      const existingAdmins = await db.collection('users')
        .find({ role: 'landlord' })
        .sort({ createdAt: 1, _id: 1 })
        .toArray()

      for (let i = 0; i < cleanedAdmins.length; i++) {
        const incoming = cleanedAdmins[i]
        const cleanEmail = String(incoming.email).trim().toLowerCase()
        const cleanName = String(incoming.name || 'Lapis Suites Admin').trim()
        const rawPhone = String(incoming.phone || '').trim()
        const cleanPhone = rawPhone ? normalizeKenyanPhone(rawPhone) : ''
        const initials = cleanName.split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase() || 'AD'

        // Match by existing ID first, then by email, then by slot index
        const target =
          (incoming.id ? existingAdmins.find((u: any) => u.id === incoming.id) : null) ||
          existingAdmins.find((u: any) => u.email.toLowerCase() === cleanEmail) ||
          existingAdmins[i] ||
          null

        if (target) {
          // Make sure email isn't already taken by a different non-target user
          const conflict = await db.collection('users').findOne({
            email: cleanEmail,
            id: { $ne: target.id }
          })
          if (conflict) {
            return res.status(409).json({ error: `Email ${cleanEmail} is already in use by another account.` })
          }

          await db.collection('users').updateOne(
            { id: target.id },
            {
              $set: {
                name: cleanName,
                email: cleanEmail,
                phone: cleanPhone,
                avatarInitials: initials,
                role: 'landlord',
                updatedAt: nowIso
              }
            }
          )
        } else {
          const defaultPassword = String(incoming.password || 'Admin@Lapis2026!')
          await db.collection('users').insertOne({
            id: generateHexObjectId(),
            email: cleanEmail,
            passwordHash: bcrypt.hashSync(defaultPassword, 10),
            name: cleanName,
            phone: cleanPhone,
            role: 'landlord',
            tenantId: null,
            unitNumber: '',
            avatarInitials: initials,
            createdAt: nowIso,
            updatedAt: nowIso
          })
        }
      }

      logServerEvent('SETTINGS', `Updated authorized admin settings (${cleanedAdmins.map((a: any) => a.email).join(', ')}) by ${req.user?.email}`)
    }

    const updatedSettings = await getAppSettings()
    const updatedAdmins = await getAuthorizedAdminsFromDb()

    logServerEvent('SETTINGS', `Saved property & billing settings (rentDueDay=${updatedSettings.rentDueDay}) by ${req.user?.email}`)
    res.json({
      ok: true,
      settings: updatedSettings,
      admins: updatedAdmins
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
