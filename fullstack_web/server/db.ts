import dns from 'dns'
import { MongoClient, Db } from 'mongodb'
import bcrypt from 'bcryptjs'
import {
  generateHexObjectId,
  MAX_ADMIN_ACCOUNTS,
  isAllowedAdminEmail
} from './config'
import { logServerEvent } from './middleware/logger'

// Ensure reliable SRV DNS resolution on Windows environments
try {
  dns.setServers(['8.8.8.8', '1.1.1.1'])
} catch {}

const MONGO_URI_AUTH = process.env.MONGODB_URI || 'mongodb://stallone:Stallone%40Mongo123@127.0.0.1:27017/propmanager?authSource=admin'
const MONGO_URI_DIRECT = 'mongodb://127.0.0.1:27017/propmanager'

let db: Db | null = null
let mongoClient: MongoClient | null = null

export function getDb(): Db {
  if (!db) {
    throw new Error('Database service is not initialized or connected')
  }
  return db
}

export function isDbConnected(): boolean {
  return db !== null
}

async function ensureCollectionsAndIndexes(database: Db) {
  try {
    const collNames = (await database.listCollections().toArray()).map(c => c.name)
    if (!collNames.includes('kcb_transactions')) {
      await database.createCollection('kcb_transactions')
      await database.collection('kcb_transactions').createIndex({ checkoutRequestId: 1 }, { sparse: true })
      await database.collection('kcb_transactions').createIndex({ merchantRequestId: 1 })
    }

    if (!collNames.includes('sms_logs')) {
      await database.createCollection('sms_logs')
    }
    await database.collection('sms_logs').createIndex({ trackingId: 1 }, { sparse: true })
    await database.collection('sms_logs').createIndex({ messageId: 1 }, { sparse: true })
    await database.collection('sms_logs').createIndex({ createdAt: -1 })

    if (!collNames.includes('payment_links')) {
      await database.createCollection('payment_links')
    }
    await database.collection('payment_links').createIndex({ linkId: 1 }, { unique: true })
    await database.collection('payment_links').createIndex({ tenantId: 1, billingMonth: 1 })
    await database.collection('payment_links').createIndex({ createdAt: -1 })

    if (!collNames.includes('public_pay_otps')) {
      await database.createCollection('public_pay_otps')
    }
    await database.collection('public_pay_otps').createIndex({ challengeId: 1 }, { unique: true })
    await database.collection('public_pay_otps').createIndex({ expiresAt: 1 })

    if (!collNames.includes('admin_stk_otps')) {
      await database.createCollection('admin_stk_otps')
    }
    await database.collection('admin_stk_otps').createIndex({ challengeId: 1 }, { unique: true })
    await database.collection('admin_stk_otps').createIndex({ expiresAt: 1 })

    if (!collNames.includes('register_otps')) {
      await database.createCollection('register_otps')
    }
    await database.collection('register_otps').createIndex({ challengeId: 1 }, { unique: true })
    await database.collection('register_otps').createIndex({ expiresAt: 1 })

    if (!collNames.includes('settings')) {
      await database.createCollection('settings')
    }
    await database.collection('settings').createIndex({ id: 1 }, { unique: true })

    if (!collNames.includes('audit_logs')) {
      await database.createCollection('audit_logs')
    }
    await database.collection('audit_logs').createIndex({ timestamp: -1 })
    await database.collection('audit_logs').createIndex({ entityType: 1, timestamp: -1 })

    if (!collNames.includes('ledger_adjustments')) {
      await database.createCollection('ledger_adjustments')
    }
    await database.collection('ledger_adjustments').createIndex({ tenantId: 1, createdAt: -1 })
    await database.collection('ledger_adjustments').createIndex({ leaseId: 1 })

    // Core financial & operational indexes (idempotency + fast filtered queries)
    try {
      await database.collection('transactions').createIndex({ reference: 1 }, { unique: true, sparse: true })
    } catch (idxErr: any) {
      logServerEvent('DB', `transactions.reference unique index notice: ${idxErr.message}`)
    }
    await database.collection('transactions').createIndex({ tenantId: 1, date: -1 })
    await database.collection('transactions').createIndex({ leaseId: 1, date: -1 })
    await database.collection('transactions').createIndex({ status: 1, date: -1 })
    await database.collection('leases').createIndex({ tenantId: 1, status: 1 })
    await database.collection('leases').createIndex({ unitId: 1, status: 1 })
    await database.collection('tenants').createIndex({ email: 1 }, { sparse: true })
    await database.collection('tenants').createIndex({ id: 1 }, { sparse: true })
    await database.collection('maintenance').createIndex({ tenantId: 1, createdAt: -1 })
    await database.collection('notifications').createIndex({ tenantId: 1, timestamp: -1 })
    await database.collection('notifications').createIndex({ role: 1, timestamp: -1 })

    // Strict 2-Admin Policy: Maximum 2 landlord/admin accounts, and each admin email
    // must include one of: musigah, stallone, odhiambo, or lapissuites.
    // Admin emails & OTP phone numbers are managed strictly in Settings (MongoDB), never .env.
    const existingAdmins = await database.collection('users')
      .find({ role: 'landlord' })
      .sort({ createdAt: 1, _id: 1 })
      .toArray()

    for (const admin of existingAdmins) {
      if (!isAllowedAdminEmail(admin.email)) {
        logServerEvent('SECURITY', `Warning: Admin account ${admin.email} does not match approved admin email policy and will be blocked at login.`)
      }
    }

    const validAdmins = existingAdmins.filter((u: any) => isAllowedAdminEmail(u.email))

    // Seed initial defaults ONLY if fewer than 2 approved admins exist (never overwrites existing DB settings/passwords/phones)
    const defaultAdmins = [
      {
        email: 'lapissuites@gmail.com',
        name: 'Lapis Suites Admin',
        initials: 'LS',
        defaultPassword: 'Admin@Lapis2026!'
      },
      {
        email: 'alex.morgan@lapissuites.com',
        name: 'Lapis Operations Admin',
        initials: 'LO',
        defaultPassword: 'Hello123@'
      }
    ]

    let activeAdminCount = validAdmins.length
    for (const candidate of defaultAdmins) {
      if (activeAdminCount >= MAX_ADMIN_ACCOUNTS) break
      const alreadyExists = await database.collection('users').findOne({ email: candidate.email })
      if (!alreadyExists) {
        logServerEvent('AUTH', `Creating authorized administrator account (${candidate.email})...`)
        await database.collection('users').insertOne({
          id: generateHexObjectId(),
          email: candidate.email,
          passwordHash: bcrypt.hashSync(candidate.defaultPassword, 10),
          name: candidate.name,
          phone: '',
          role: 'landlord',
          avatarInitials: candidate.initials,
          createdAt: new Date().toISOString()
        })
        activeAdminCount++
      }
    }

    // Initialize standard unit type configurations if empty (Studio, 1-Bedroom, 2-Bedroom)
    const unitTypeCount = await database.collection('unit_types').countDocuments()
    if (unitTypeCount === 0) {
      logServerEvent('DB', 'Initializing standard unit type configurations...')
      await database.collection('unit_types').insertMany([
        {
          id: generateHexObjectId(),
          key: 'studio',
          name: 'Studio Suite',
          baseRent: 35000,
          depositMultiplier: 1,
          description: 'Open plan studio with kitchenette and private balcony',
          features: ['Kitchenette', 'Balcony', 'High-Speed Wi-Fi', 'En-suite Bathroom']
        },
        {
          id: generateHexObjectId(),
          key: 'one-bedroom',
          name: 'One-Bedroom Executive',
          baseRent: 50000,
          depositMultiplier: 1,
          description: 'Spacious one-bedroom with separate living area and fitted kitchen',
          features: ['Fitted Kitchen', 'Balcony', 'Dedicated Parking', 'En-suite Bathroom', 'High-Speed Wi-Fi']
        },
        {
          id: generateHexObjectId(),
          key: 'two-bedroom',
          name: 'Two-Bedroom Deluxe',
          baseRent: 75000,
          depositMultiplier: 1,
          description: 'Luxury two-bedroom master en-suite with executive living space',
          features: ['Master En-suite', 'Guest Bathroom', 'Fitted Kitchen', 'Two Balconies', '2 Parking Slots']
        }
      ])
    }
  } catch (err: any) {
    logServerEvent('DB', `Index initialization notice: ${err.message}`)
  }
}

export async function connectMongo(): Promise<Db> {
  const isAtlas = MONGO_URI_AUTH.includes('mongodb+srv') || MONGO_URI_AUTH.includes('mongodb.net')
  const hostLabel = isAtlas ? 'MongoDB Atlas Cloud' : '127.0.0.1:27017'

  try {
    mongoClient = new MongoClient(MONGO_URI_AUTH, { serverSelectionTimeoutMS: 8000 })
    await mongoClient.connect()
    db = mongoClient.db('propmanager')
    logServerEvent('DB', `Connected successfully to ${hostLabel}`)
    await ensureCollectionsAndIndexes(db)
    return db
  } catch (errAuth: any) {
    logServerEvent('DB', `Primary connection failed (${errAuth.message}), attempting fallback connection...`)
    try {
      mongoClient = new MongoClient(MONGO_URI_DIRECT, { serverSelectionTimeoutMS: 3000 })
      await mongoClient.connect()
      db = mongoClient.db('propmanager')
      logServerEvent('DB', 'Connected successfully to MongoDB at 127.0.0.1:27017 (direct fallback)')
      await ensureCollectionsAndIndexes(db)
      return db
    } catch (errDirect: any) {
      logServerEvent('DB', `CRITICAL: Could not connect to MongoDB: ${errDirect.message}`)
      throw errDirect
    }
  }
}
