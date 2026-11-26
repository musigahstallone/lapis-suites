import { MongoClient } from 'mongodb'
import bcrypt from 'bcryptjs'

const MONGO_URI_AUTH = process.env.MONGODB_URI || 'mongodb://stallone:Stallone%40Mongo123@127.0.0.1:27017/propmanager?authSource=admin'
const MONGO_URI_DIRECT = 'mongodb://127.0.0.1:27017/propmanager'

async function checkDatabase() {
  console.log('[Seed CLI] Checking MongoDB database state...')
  let client: MongoClient
  try {
    client = new MongoClient(MONGO_URI_AUTH)
    await client.connect()
    console.log('[Seed CLI] Connected via authenticated URI.')
  } catch (_errAuth: any) {
    console.warn('[Seed CLI] Authenticated connection failed, attempting direct local connection...')
    client = new MongoClient(MONGO_URI_DIRECT)
    await client.connect()
    console.log('[Seed CLI] Connected via direct URI.')
  }

  try {
    const db = client.db('propmanager')
    const userCount = await db.collection('users').countDocuments()
    if (userCount === 0) {
      console.log('[Seed CLI] Initializing standard user accounts...')
      const defaultHash = bcrypt.hashSync('Hello123@', 10)
      const adminHash = bcrypt.hashSync('Admin@Lapis2026!', 10)
      const initialUsers = [
        {
          id: '65f1a2b3c4d5e6f7a8b90998',
          email: 'lapissuites@gmail.com',
          passwordHash: adminHash,
          name: 'Lapis Suites Admin',
          phone: '',
          role: 'landlord',
          tenantId: null,
          unitNumber: '',
          avatarInitials: 'LS',
          createdAt: new Date().toISOString()
        },
        {
          id: '65f1a2b3c4d5e6f7a8b90999',
          email: 'alex.morgan@lapissuites.com',
          passwordHash: defaultHash,
          name: 'Alex Morgan',
          phone: '',
          role: 'landlord',
          tenantId: null,
          unitNumber: '',
          avatarInitials: 'AM',
          createdAt: new Date().toISOString()
        },
        {
          id: '65f1a2b3c4d5e6f7a8b90301',
          email: 'elena.vance@lapissuites.com',
          passwordHash: defaultHash,
          name: 'Elena Vance',
          role: 'tenant',
          tenantId: '65f1a2b3c4d5e6f7a8b90301',
          unitNumber: '6604',
          avatarInitials: 'EV',
          createdAt: new Date().toISOString()
        },
        {
          id: '65f1a2b3c4d5e6f7a8b90302',
          email: 'marcus.brody@gmail.com',
          passwordHash: defaultHash,
          name: 'Marcus Brody',
          role: 'tenant',
          tenantId: '65f1a2b3c4d5e6f7a8b90302',
          unitNumber: '101',
          avatarInitials: 'MB',
          createdAt: new Date().toISOString()
        }
      ]
      await db.collection('users').insertMany(initialUsers)
      console.log('[Seed CLI] Users created successfully.')
    } else {
      console.log(`[Seed CLI] Database has ${userCount} user accounts.`)
    }

    const unitCount = await db.collection('units').countDocuments()
    const leaseCount = await db.collection('leases').countDocuments()
    const tenantCount = await db.collection('tenants').countDocuments()
    const unitTypeCount = await db.collection('unit_types').countDocuments()
    const txCount = await db.collection('transactions').countDocuments()

    console.log(`[Seed CLI] Current DB state:`)
    console.log(`  - Unit Types: ${unitTypeCount}`)
    console.log(`  - Units: ${unitCount}`)
    console.log(`  - Tenants: ${tenantCount}`)
    console.log(`  - Leases: ${leaseCount}`)
    console.log(`  - Transactions: ${txCount} (All payments purged per user instruction)`)
  } catch (err: any) {
    console.error('[Seed CLI] Failed with error:', err.message)
    process.exit(1)
  } finally {
    await client.close()
  }
}

checkDatabase()
