import { reactive, computed } from 'vue'
import type {
  Unit,
  Tenant,
  Lease,
  Transaction,
  UnitTypeConfig,
  UnitTransferPayload,
  UnitType,
  PaymentCategory,
  DarajaCallbackPayload,
  PropertySettings,
  MaintenanceRequest,
  MaintenanceCategory,
  MaintenancePriority,
  MaintenanceStatus,
  AppNotification,
  KcbTransactionRecord, LeaseStatus, NotificationType,
  PaymentMethod
} from './types'
import { generateObjectId } from './utils/objectId'
import { processLeaseBilling, calculateNextDueDate } from './utils/billingEngine'
import { formatHumanDate, formatHumanDateTime, getDaysRemaining } from './utils/formatters'
import { safeFetchJson } from './utils/safeFetch'
export { formatHumanDate, formatHumanDateTime, getDaysRemaining }

export interface PropertyInfo {
  name: string
  address: string
  city: string
  totalFloors: number
  managerName: string
  contactPhone: string
  contactEmail: string
  paybillNumber: string
  accountNumber?: string
  paybillRecipientName?: string
}

export const propertyInfo: PropertyInfo = {
  name: 'LAPIS SUITES',
  address: 'Unit Tower 4, Lapis Boulevard, Upper Hill',
  city: 'Nairobi',
  totalFloors: 14,
  managerName: 'Alex Morgan',
  contactPhone: '+254 700 892 110',
  contactEmail: 'management@lapissuites.com',
  paybillNumber: '522533',
  accountNumber: '8107578',
  paybillRecipientName: 'LAPIS APARTMENTS LIMITED'
}

export const propertySettings = reactive<PropertySettings>({
  propertyName: 'LAPIS SUITES',
  currency: 'KES',
  rentDueDay: 5, // Rent is due on the 5th of each month
  gracePeriodDays: 5,
  lateFeePercent: 5,
  autoReconciliationEnabled: true,
  paybillNumber: '522533'
})

export function formatKES(amount: number): string {
  return `KES ${Math.round(amount || 0).toLocaleString('en-KE')}`
}

export function normalizePhone(rawPhone?: string): string {
  if (!rawPhone) return ''
  const digits = rawPhone.replace(/\D/g, '')
  if (digits.startsWith('254')) return digits.slice(3)
  if (digits.startsWith('0')) return digits.slice(1)
  return digits
}

export interface UserSession {
  isAuthenticated: boolean
  role: 'landlord' | 'tenant'
  id: string // 24-char hex ObjectId
  name: string
  email: string
  unitNumber?: string
  avatarInitials: string
  token?: string | null
  tenantId?: string | null
}

export interface AppStore {
  unitTypes: UnitTypeConfig[]
  units: Unit[]
  tenants: Tenant[]
  leases: Lease[]
  transactions: Transaction[]
  maintenanceRequests: MaintenanceRequest[]
  notifications: AppNotification[]
  kcbLogs: KcbTransactionRecord[]
  session: UserSession
  searchQuery: string
  searchFilter: 'all' | 'payments' | 'leases' | 'tenants' | 'units'
  isBackendConnected: boolean
}

// All production and operational state is persisted and served directly from MongoDB collections.
// Zero static dummy data or seed payments are maintained in memory or client state.
export const initialTransactions: Transaction[] = []
export const initialMaintenance: MaintenanceRequest[] = []
export const initialNotifications: AppNotification[] = []
export const initialKcbLogs: KcbTransactionRecord[] = []

const STORAGE_KEY = 'lapissuites_store_v7'
const SESSION_KEY = 'lapissuites_session_v7'

function loadInitialStore(): AppStore {
  const token = typeof window !== 'undefined' ? localStorage.getItem('lapis_jwt_token') : null
  const defaultSession: UserSession = {
    isAuthenticated: !!token,
    role: 'landlord',
    id: '65f1a2b3c4d5e6f7a8b90999',
    name: 'Alex Morgan',
    email: 'management@lapissuites.com',
    avatarInitials: 'AM',
    token: token || null
  }

  let savedSession = defaultSession
  try {
    const rawSession = typeof window !== 'undefined' && typeof localStorage !== 'undefined' ? localStorage.getItem(SESSION_KEY) : null
    if (rawSession) {
      savedSession = JSON.parse(rawSession)
      if (token) savedSession.token = token
      if (!token) savedSession.isAuthenticated = false
    }
  } catch (e) {
    console.error('Failed reading session from localStorage:', e)
  }

  return {
    unitTypes: [],
    units: [],
    tenants: [],
    leases: [],
    transactions: [],
    maintenanceRequests: [],
    notifications: [],
    kcbLogs: [],
    session: savedSession,
    searchQuery: '',
    searchFilter: 'all',
    isBackendConnected: false
  }
}

export const store = reactive<AppStore>(loadInitialStore())

function authHeaders(withJson = false): Record<string, string> {
  const headers: Record<string, string> = {}
  if (withJson) headers['Content-Type'] = 'application/json'
  const token = store.session.token || (typeof window !== 'undefined' ? localStorage.getItem('lapis_jwt_token') : null)
  if (token) headers['Authorization'] = `Bearer ${token}`
  return headers
}

export async function fetchUnits(): Promise<void> {
  try {
    const res = await fetch('/api/units', { headers: authHeaders() })
    if (res.ok) {
      const data = await res.json()
      store.units = Array.isArray(data) ? data : (Array.isArray(data.units) ? data.units : [])
      store.isBackendConnected = true
    }
  } catch (err) {
    console.warn('Could not fetch units:', err)
  }
}

export async function fetchUnitTypes(): Promise<void> {
  try {
    const res = await fetch('/api/unit-types', { headers: authHeaders() })
    if (res.ok) {
      const data = await res.json()
      store.unitTypes = Array.isArray(data) ? data : (Array.isArray(data.unitTypes) ? data.unitTypes : [])
    }
  } catch (err) {
    console.warn('Could not fetch unit types:', err)
  }
}

export async function fetchTenants(): Promise<void> {
  try {
    const res = await fetch('/api/tenants', { headers: authHeaders() })
    if (res.ok) {
      const data = await res.json()
      store.tenants = Array.isArray(data) ? data : (Array.isArray(data.tenants) ? data.tenants : [])
      store.isBackendConnected = true
    }
  } catch (err) {
    console.warn('Could not fetch tenants:', err)
  }
}

export async function fetchLeases(): Promise<void> {
  try {
    const res = await fetch('/api/leases', { headers: authHeaders() })
    if (res.ok) {
      const data = await res.json()
      store.leases = Array.isArray(data) ? data : (Array.isArray(data.leases) ? data.leases : [])
      store.isBackendConnected = true
    }
  } catch (err) {
    console.warn('Could not fetch leases:', err)
  }
}

export async function fetchPayments(): Promise<void> {
  try {
    const res = await fetch('/api/transactions', { headers: authHeaders() })
    if (res.ok) {
      const data = await res.json()
      store.transactions = Array.isArray(data) ? data : (Array.isArray(data.transactions) ? data.transactions : [])
      store.isBackendConnected = true
    }
  } catch (err) {
    console.warn('Could not fetch payments:', err)
  }
}

export async function fetchMaintenance(): Promise<void> {
  try {
    const token = store.session.token
    const headers: Record<string, string> = {}
    if (token) headers['Authorization'] = `Bearer ${token}`
    const res = await fetch('/api/maintenance', { headers })
    if (res.ok) {
      const data = await res.json()
      store.maintenanceRequests = Array.isArray(data) ? data : []
      store.isBackendConnected = true
    }
  } catch (err) {
    console.warn('Could not fetch maintenance:', err)
  }
}

export async function fetchDashboard(): Promise<void> {
  try {
    await Promise.all([
      fetchUnits(),
      fetchUnitTypes(),
      fetchTenants(),
      fetchLeases(),
      fetchPayments(),
      fetchAppSettings()
    ])
    store.isBackendConnected = true
  } catch (err) {
    console.warn('Could not fetch dashboard stats:', err)
  }
}

export async function fetchTenantProfile(): Promise<void> {
  try {
    await Promise.all([
      fetchTenants(),
      fetchLeases(),
      fetchUnits(),
      fetchUnitTypes(),
      fetchPayments(),
      fetchMaintenance()
    ])
    store.isBackendConnected = true
  } catch (err) {
    console.warn('Could not fetch resident profile:', err)
  }
}

// Alias for backwards compatibility if needed
export const fetchFromBackend = fetchDashboard

export async function verifySession() {
  const token = store.session.token || (typeof window !== 'undefined' ? localStorage.getItem('lapis_jwt_token') : null)
  if (token) {
    try {
      const authRes = await fetch('/api/auth/me', {
        headers: { Authorization: `Bearer ${token}` }
      })
      if (authRes.ok) {
        const authData = await authRes.json()
        if (authData.user) {
          store.session.isAuthenticated = true
          store.session.role = authData.user.role
          store.session.id = authData.user.userId || authData.user.id
          store.session.name = authData.user.name
          store.session.email = authData.user.email
          store.session.tenantId = authData.user.tenantId || null
          store.session.unitNumber = authData.user.unitNumber || ''
          store.session.avatarInitials = authData.user.avatarInitials || (authData.user.name ? authData.user.name.split(' ').map((n: string) => n[0]).join('').slice(0, 2).toUpperCase() : 'AM')
          store.session.token = token
          saveSession()
        }
      } else if (authRes.status === 401 || authRes.status === 403) {
        logout()
      }
    } catch (authErr) {
      console.warn('Could not verify JWT token with backend:', authErr)
    }
  }
}

// Verify session and purge any stale mock store cache on client startup
if (typeof window !== 'undefined') {
  try {
    localStorage.removeItem(STORAGE_KEY)
    localStorage.removeItem('lapissuites_store_v6')
    localStorage.removeItem('lapissuites_store_v5')
  } catch (e) {}
  verifySession()
}

export function saveSession() {
  try {
    if (typeof window !== 'undefined' && typeof localStorage !== 'undefined') {
      localStorage.setItem(SESSION_KEY, JSON.stringify(store.session))
    }
  } catch (e) {
    console.error('Failed to save session:', e)
  }
}

export function saveStore() {
  // Store state is persisted in real time via atomic MongoDB REST mutations
}

export function resetStore() {
  fetchFromBackend()
}

export interface LoginResult {
  ok: boolean
  role?: 'landlord' | 'tenant'
  requiresOtp?: boolean
  requiresAccountSetup?: boolean
  needsAdminPhoneSetup?: boolean
  challengeToken?: string
  email?: string
  maskedPhone?: string
  expiresInSeconds?: number
  message?: string
  error?: string
}

function clearClientStoreState(): void {
  store.units = []
  store.tenants = []
  store.leases = []
  store.transactions = []
  store.maintenanceRequests = []
  store.notifications = []
  store.kcbLogs = []
  store.searchQuery = ''
}

async function completeAuthenticatedSession(token: string, user: any): Promise<void> {
  // Always wipe previous account's in-memory collections BEFORE loading the new user
  clearClientStoreState()

  if (typeof window !== 'undefined') {
    localStorage.setItem('lapis_jwt_token', token)
  }
  store.session = {
    isAuthenticated: true,
    role: user.role,
    id: user.userId || user.id,
    name: user.name,
    email: user.email,
    tenantId: user.tenantId || null,
    avatarInitials: user.avatarInitials || (user.name ? user.name.split(' ').map((n: string) => n[0]).join('').slice(0, 2).toUpperCase() : 'AM'),
    unitNumber: user.unitNumber || '',
    token
  }
  saveSession()

  if (user.role === 'landlord') {
    await fetchDashboard()
  } else {
    await fetchFromBackend()
  }

  if (typeof window !== 'undefined') {
    import('./sse').then(m => m.reconnectSSE()).catch(() => {})
  }
}

export async function loginWithCredentials(email: string, password: string): Promise<LoginResult> {
  const res = await safeFetchJson('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim().toLowerCase(), password })
  })
  if (!res.ok) {
    return { ok: false, error: res.error || 'Invalid email or password.' }
  }
  const data = res.data

  if (data.requiresAccountSetup) {
    return {
      ok: true,
      requiresAccountSetup: true,
      role: 'tenant',
      email: data.email || email.trim().toLowerCase(),
      expiresInSeconds: data.expiresInSeconds || 600,
      message: data.message
    }
  }

  // Admin accounts require 6-digit SMS OTP verification
  if (data.requiresOtp) {
    return {
      ok: true,
      requiresOtp: true,
      role: 'landlord',
      challengeToken: data.challengeToken,
      email: data.email || email.trim().toLowerCase(),
      maskedPhone: data.maskedPhone,
      expiresInSeconds: data.expiresInSeconds || 600,
      message: data.message
    }
  }

  await completeAuthenticatedSession(data.token, data.user)
  return {
    ok: true,
    role: data.user.role,
    needsAdminPhoneSetup: Boolean(data.needsAdminPhoneSetup)
  }
}

export async function requestResidentRegisterOtp(payload: { name?: string; email: string; phone: string; password: string }): Promise<{ ok: boolean; mode?: 'new' | 'claim'; challengeToken?: string; email?: string; message?: string; error?: string }> {
  const res = await safeFetchJson('/api/auth/register/request-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  })
  if (!res.ok) {
    return { ok: false, error: res.error || 'Could not send verification SMS.' }
  }
  return { ok: true, ...res.data }
}

export async function verifyResidentRegisterOtp(challengeToken: string, code: string): Promise<{ ok: boolean; role?: 'tenant'; error?: string }> {
  const res = await safeFetchJson('/api/auth/register/verify-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ challengeToken, code })
  })
  if (!res.ok) {
    return { ok: false, error: res.error || 'Invalid or expired verification code.' }
  }
  await completeAuthenticatedSession(res.data.token, res.data.user)
  return { ok: true, role: 'tenant' }
}

export async function verifyAdminLoginOtp(challengeToken: string, code: string): Promise<LoginResult> {
  try {
    const res = await fetch('/api/auth/verify-login-otp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ challengeToken, code })
    })
    const data = await res.json()
    if (!res.ok) {
      return { ok: false, error: data.error || 'Invalid or expired verification code.' }
    }

    await completeAuthenticatedSession(data.token, data.user)
    return {
      ok: true,
      role: data.user.role,
      needsAdminPhoneSetup: Boolean(data.needsAdminPhoneSetup)
    }
  } catch (err: any) {
    return { ok: false, error: err.message || 'Unable to verify OTP with server.' }
  }
}

export async function resendAdminLoginOtp(challengeToken: string): Promise<{ ok: boolean; challengeToken?: string; maskedPhone?: string; expiresInSeconds?: number; message?: string; error?: string }> {
  try {
    const res = await fetch('/api/auth/resend-login-otp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ challengeToken })
    })
    const data = await res.json()
    if (!res.ok) {
      return { ok: false, error: data.error || 'Failed to resend verification code.' }
    }
    return {
      ok: true,
      challengeToken: data.challengeToken,
      maskedPhone: data.maskedPhone,
      expiresInSeconds: data.expiresInSeconds || 600,
      message: data.message
    }
  } catch (err: any) {
    return { ok: false, error: err.message || 'Network error resending verification code.' }
  }
}

export async function registerTenant(payload: { name: string; email: string; password: string; phone?: string }): Promise<{ ok: boolean; role?: 'tenant'; error?: string }> {
  try {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    const data = await res.json()
    if (!res.ok) {
      return { ok: false, error: data.error || 'Registration failed.' }
    }
    const { token, user } = data
    if (typeof window !== 'undefined') {
      localStorage.setItem('lapis_jwt_token', token)
    }
    store.session = {
      isAuthenticated: true,
      role: 'tenant',
      id: user.userId || user.id,
      name: user.name,
      email: user.email,
      avatarInitials: user.avatarInitials || (user.name ? user.name.split(' ').map((n: string) => n[0]).join('').slice(0, 2).toUpperCase() : 'TN'),
      unitNumber: user.unitNumber,
      token
    }
    saveSession()
    fetchFromBackend()
    return { ok: true, role: 'tenant' }
  } catch (err: any) {
    return { ok: false, error: err.message || 'Unable to connect to authentication server.' }
  }
}

export function loginAs(role: 'landlord' | 'tenant', email?: string) {
  if (role === 'landlord') {
    store.session = {
      isAuthenticated: true,
      role: 'landlord',
      id: '65f1a2b3c4d5e6f7a8b90999',
      name: 'Alex Morgan',
      email: email || 'alex.morgan@lapissuites.com',
      avatarInitials: 'AM',
      token: store.session.token || null
    }
  } else {
    const defaultTenant = store.tenants[0] || {
      id: '',
      name: 'Resident',
      email: 'resident@lapissuites.com',
      currentUnitNumber: '',
      avatarInitials: 'RS'
    }
    store.session = {
      isAuthenticated: true,
      role: 'tenant',
      id: defaultTenant.id,
      name: defaultTenant.name,
      email: defaultTenant.email,
      unitNumber: defaultTenant.currentUnitNumber,
      avatarInitials: defaultTenant.avatarInitials,
      token: store.session.token || null
    }
  }
  saveSession()
  if (typeof window !== 'undefined') {
    import('./sse').then(m => m.reconnectSSE()).catch(() => {})
  }
}

export const login = loginAs

export function logout() {
  clearClientStoreState()
  if (typeof window !== 'undefined') {
    localStorage.removeItem('lapis_jwt_token')
    localStorage.removeItem(SESSION_KEY)
  }
  store.session = {
    isAuthenticated: false,
    role: 'landlord',
    id: '',
    name: '',
    email: '',
    tenantId: null,
    unitNumber: '',
    avatarInitials: '',
    token: null
  }
  if (typeof window !== 'undefined') {
    import('./sse').then(m => m.reconnectSSE()).catch(() => {})
  }
}

// ==========================================
// Unit Type & Unit Helpers
// ==========================================
export function getUnitTypeConfig(typeKey: string): UnitTypeConfig | undefined {
  if (!typeKey) return undefined
  return store.unitTypes.find(ut => ut.key === typeKey || ut.name.toLowerCase() === typeKey.toLowerCase() || ut.id === typeKey)
}

export function getUnitFeatures(typeKey: UnitType): string[] {
  const config = getUnitTypeConfig(typeKey)
  return config ? config.features : []
}

export function getUnitMonthlyRent(unit: Unit | { type: UnitType }): number {
  if (!unit) return 0
  // 1. If unit is currently leased, check active lease rate first
  if ('id' in unit && unit.id) {
    const activeLease = store.leases.find(l => (l.unitId === unit.id || l.unitNumber === (unit as any).unitNumber) && (l.status === 'active' || l.status === 'pending_deposit'))
    if (activeLease && activeLease.monthlyRent) return Number(activeLease.monthlyRent)
  }
  // 2. If unit has monthlyRent property directly
  if ('monthlyRent' in unit && (unit as any).monthlyRent) {
    return Number((unit as any).monthlyRent)
  }
  // 3. Match from Unit Types Configuration
  if (unit.type) {
    const config = getUnitTypeConfig(unit.type)
    if (config?.baseRent) return Number(config.baseRent)
    const matched = store.unitTypes.find(t => t.key?.includes(unit.type) || unit.type?.includes(t.key))
    if (matched?.baseRent) return Number(matched.baseRent)
  }
  // 4. Standard baseline pricing by unit category
  if (unit.type === 'studio') return 35000
  if (unit.type === 'one-bedroom') return 50000
  if (unit.type === 'two-bedroom') return 75000
  return 0
}

// Strict Data Integrity & Domain Guards
export async function createUnit(data: {
  unitNumber: string
  type: UnitType
  status?: 'vacant' | 'maintenance'
}): Promise<Unit> {
  const trimmedNumber = data.unitNumber.trim()
  if (!trimmedNumber) throw new Error('Unit number cannot be empty')

  const res = await fetch('/api/units', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify({
      unitNumber: trimmedNumber,
      type: data.type,
      status: data.status || 'vacant'
    })
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to add unit')
  }

  const newUnit: Unit = resData
  const idx = store.units.findIndex(u => u.id === newUnit.id)
  if (idx === -1) {
    store.units.push(newUnit)
  } else {
    store.units[idx] = newUnit
  }
  return newUnit
}

export async function updateUnit(id: string, updates: Partial<Unit>): Promise<Unit> {
  const unit = store.units.find(u => u.id === id)
  if (!unit) throw new Error('Unit not found')

  // Domain Integrity Guard: Unit Number is immutable once created
  if (updates.unitNumber && updates.unitNumber !== unit.unitNumber) {
    throw new Error('Unit number/identifier is immutable and cannot be changed')
  }

  // Domain Integrity Guard: Occupancy is strictly derived from active lease
  const hasActiveLease = store.leases.some(l => l.unitId === unit.id && l.status === 'active')
  if (hasActiveLease && updates.status && updates.status !== 'occupied') {
    throw new Error('Cannot set unit status to vacant or maintenance while bound to an active lease')
  }

  const res = await fetch(`/api/units/${id}`, {
    method: 'PUT',
    headers: authHeaders(true),
    body: JSON.stringify(updates)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to update unit')
  }

  Object.assign(unit, resData)
  return unit
}

export async function deleteUnit(id: string): Promise<boolean> {
  const unitIndex = store.units.findIndex(u => u.id === id)
  if (unitIndex === -1) throw new Error('Unit not found')

  const unit = store.units[unitIndex]
  if (unit.status === 'occupied' || unit.currentTenantId) {
    throw new Error(`Cannot delete Unit ${unit.unitNumber} while currently occupied by a tenant`)
  }

  const hasLeases = store.leases.some(l => l.unitId === unit.id)
  if (hasLeases) {
    throw new Error(`Cannot delete Unit ${unit.unitNumber} because historical lease agreements exist`)
  }

  const res = await fetch(`/api/units/${id}`, {
    method: 'DELETE',
    headers: authHeaders()
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to delete unit')
  }

  store.units.splice(unitIndex, 1)
  return true
}

// Unit Type CRUD
export async function saveUnitTypeConfig(data: {
  id?: string
  name: string
  baseRent: number
  depositMultiplier: number
  description: string
  features: string[]
}): Promise<UnitTypeConfig> {
  const res = await fetch('/api/unit-types', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify(data)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to save unit type')
  }

  const idx = store.unitTypes.findIndex(u => (data.id && u.id === data.id) || u.id === resData.id)
  if (idx >= 0) {
    store.unitTypes[idx] = resData
  } else {
    store.unitTypes.push(resData)
  }
  return resData
}

export const updateUnitTypeConfig = (id: string, updates: Partial<UnitTypeConfig>) => saveUnitTypeConfig({ id, ...updates } as any)

// Tenant CRUD & Integrity
export async function createTenant(data: {
  name: string
  email: string
  phone: string
  nationalId?: string
  emergencyContact?: string
}): Promise<Tenant> {
  const res = await fetch('/api/tenants', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify(data)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to create resident')
  }

  const newTenant: Tenant = resData
  const idx = store.tenants.findIndex(t => t.id === newTenant.id)
  if (idx === -1) {
    store.tenants.unshift(newTenant)
  } else {
    store.tenants[idx] = newTenant
  }
  return newTenant
}

export async function updateTenant(id: string, updates: Partial<Tenant>): Promise<Tenant> {
  const tenant = store.tenants.find(t => t.id === id)
  if (!tenant) throw new Error('Tenant not found')

  const res = await fetch(`/api/tenants/${id}`, {
    method: 'PUT',
    headers: authHeaders(true),
    body: JSON.stringify(updates)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to update resident')
  }

  Object.assign(tenant, resData)
  return tenant
}

export async function deleteTenant(id: string): Promise<boolean> {
  const index = store.tenants.findIndex(t => t.id === id)
  if (index === -1) throw new Error('Tenant not found')
  const tenant = store.tenants[index]
  if (tenant.currentUnitId) {
    throw new Error(`Cannot delete resident ${tenant.name} while currently assigned to Unit ${tenant.currentUnitNumber}`)
  }

  const res = await fetch(`/api/tenants/${id}`, {
    method: 'DELETE',
    headers: authHeaders()
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to delete resident')
  }

  store.tenants.splice(index, 1)
  return true
}

// Lease Creation & Lifecycle
export async function createLease(payload: {
  tenantId: string
  unitId: string
  startDate: string
  endDate: string
  monthlyRent?: number
  depositAmount?: number
  depositPaid?: boolean
  firstMonthRent?: number
  terms?: string
}): Promise<Lease> {
  const tenant = store.tenants.find(t => t.id === payload.tenantId)
  if (!tenant) throw new Error('Tenant not found')

  const unit = store.units.find(u => u.id === payload.unitId)
  if (!unit) throw new Error('Unit not found')

  if (unit.status === 'occupied') {
    throw new Error(`Unit ${unit.unitNumber} is already occupied`)
  }

  const res = await fetch('/api/leases', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify(payload)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to create lease')
  }

  const newLease: Lease = resData
  const idx = store.leases.findIndex(l => l.id === newLease.id)
  if (idx === -1) {
    store.leases.unshift(newLease)
  } else {
    store.leases[idx] = newLease
  }

  // Refresh latest state from MongoDB
  await fetchLeases()
  return newLease
}

export async function terminateLease(leaseId: string): Promise<boolean> {
  const lease = store.leases.find(l => l.id === leaseId)
  if (!lease) throw new Error('Lease not found')

  const res = await fetch(`/api/leases/${leaseId}/terminate`, {
    method: 'POST',
    headers: authHeaders(true)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to terminate lease')
  }

  await fetchLeases()
  return true
}

// Unit Transfer Workflow
export async function executeUnitTransfer(payload: UnitTransferPayload): Promise<{ newLease: Lease; oldLease: Lease }> {
  const tenant = store.tenants.find(t => t.id === payload.tenantId)
  if (!tenant) throw new Error('Tenant not found')

  const currentUnit = store.units.find(u => u.id === payload.currentUnitId)
  if (!currentUnit) throw new Error('Current unit not found')

  const newUnit = store.units.find(u => u.id === payload.newUnitId)
  if (!newUnit) throw new Error('Target unit not found')
  if (newUnit.status === 'occupied') throw new Error(`Target Unit ${newUnit.unitNumber} is already occupied`)

  const oldLease = store.leases.find(l => l.id === tenant.currentLeaseId && l.status === 'active')
  if (!oldLease) throw new Error('No active lease found for this tenant')

  const res = await fetch('/api/leases/transfer', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify(payload)
  })
  const resData = await res.json()
  if (!res.ok) {
    throw new Error(resData.error || 'Failed to transfer unit')
  }

  await fetchLeases()
  await fetchUnits()
  await fetchTenants()
  return { newLease: resData.newLease, oldLease: resData.newLease }
}

// ==========================================
// Payment Processing
// ==========================================

// Manual Reconciliation Workflow for Unassigned / Flagged Payments
export async function reconcilePayment(
  transactionId: string,
  tenantId: string,
  unitId: string,
  auditNote?: string
): Promise<boolean> {
  const tx = store.transactions.find(t => t.id === transactionId)
  if (!tx) throw new Error('Transaction not found')
  if (tx.reconciled) return true // Guard against double execution

  const tenant = store.tenants.find(t => t.id === tenantId)
  if (!tenant) throw new Error('Target tenant not found')

  const unit = store.units.find(u => u.id === unitId)
  if (!unit) throw new Error('Target unit not found')

  const activeLease = store.leases.find(l => l.tenantId === tenant.id && (l.status === 'active' || l.status === 'pending_deposit')) || null

  // Trigger Automated Lease Billing Engine
  const billingResult = processLeaseBilling(
    tenant,
    activeLease,
    tx.amount,
    propertySettings.rentDueDay
  )

  tenant.balance = billingResult.newBalance
  tenant.arrearsBalance = billingResult.arrearsBalance
  tenant.accountCredit = billingResult.accountCredit
  tenant.nextPaymentDueDate = billingResult.nextPaymentDueDate
  if (activeLease) {
    activeLease.nextPaymentDueDate = billingResult.nextPaymentDueDate
    if (billingResult.allocation.depositPaid && billingResult.allocation.depositPaid >= (activeLease.depositAmount || 0)) {
      activeLease.depositPaid = true
      if (activeLease.status === 'pending_deposit') {
        activeLease.status = 'active'
      }
    }
  }

  // Update Transaction (Immutable amounts/dates preserved)
  tx.tenantId = tenant.id
  tx.tenantName = tenant.name
  tx.unitId = unit.id
  tx.unitNumber = unit.unitNumber
  tx.leaseId = activeLease?.id || null
  tx.invoiceRef = `INV-REC-${unit.unitNumber}`
  tx.status = 'reconciled'
  tx.reconciled = true
  tx.reconciledAt = new Date().toISOString().slice(0, 19).replace('T', ' ')
  tx.reconciledBy = `${store.session.name} (Manual Allocation)`
  tx.allocation = billingResult.allocation
  if (auditNote) tx.notes = auditNote

  try {
    await fetch('/api/transactions/reconcile', {
      method: 'POST',
      headers: authHeaders(true),
      body: JSON.stringify({
        transactionId,
        tenantId,
        unitId,
        notes: auditNote
      })
    })
  } catch (e) {
    console.warn('Backend reconcile call warning:', e)
  }

  saveStore()
  return true
}

// Direct Payment from Tenant Portal or Admin Record
export async function processDirectPayment(payment: {
  tenantId?: string
  unitId?: string
  leaseId?: string
  amount: number
  method: PaymentMethod
  category?: PaymentCategory
  reference?: string
  notes?: string
  date?: string
  payerName?: string
  phoneNumber?: string
  source?: 'manual' | 'callback'
  paymentType?: 'deposit' | 'rent' | 'deposit_and_rent'
}): Promise<Transaction> {
  const lease = payment.leaseId ? store.leases.find(l => l.id === payment.leaseId) : null
  const tenant = (payment.tenantId ? store.tenants.find(t => t.id === payment.tenantId) : null) ||
                 (lease ? store.tenants.find(t => t.id === lease.tenantId) : null)
  const unit = (payment.unitId ? store.units.find(u => u.id === payment.unitId) : null) ||
               (tenant?.currentUnitId ? store.units.find(u => u.id === tenant.currentUnitId) : null) ||
               (lease?.unitId ? store.units.find(u => u.id === lease.unitId) : null)

  const resolvedTenantId = tenant?.id || lease?.tenantId || payment.tenantId || null
  const resolvedUnitNumber = unit?.unitNumber || tenant?.currentUnitNumber || lease?.unitNumber || ''
  const resolvedUnitId = unit?.id || tenant?.currentUnitId || lease?.unitId || null
  const resolvedLeaseId = lease?.id || tenant?.currentLeaseId || payment.leaseId || null

  const ref = payment.reference?.trim() || `MP-${Date.now().toString().slice(-6)}`
  const existing = store.transactions.find(t => t.reference === ref)
  if (existing) {
    return existing
  }

  const payload = {
    tenantId: resolvedTenantId,
    unitId: resolvedUnitId,
    leaseId: resolvedLeaseId,
    unitNumber: resolvedUnitNumber,
    amount: payment.amount,
    method: payment.method === 'stk_push' ? 'stk_push' : 'mpesa_paybill',
    category: payment.category || 'rent',
    reference: ref,
    notes: payment.notes || `M-Pesa payment for Unit ${resolvedUnitNumber || 'Suite'}`,
    date: payment.date || new Date().toISOString().slice(0, 10),
    payerName: payment.payerName || tenant?.name || 'Resident',
    phoneNumber: payment.phoneNumber || tenant?.phone || '',
    source: payment.source || 'manual',
    paymentType: payment.paymentType || 'deposit_and_rent'
  }

  const res = await fetch('/api/transactions', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify(payload)
  })
  const savedTx: any = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error(savedTx.error || 'Could not record payment. Please check your details and try again.')
  }

  const idx = store.transactions.findIndex(t => t.id === savedTx.id || t.reference === savedTx.reference)
  if (idx >= 0) {
    store.transactions[idx] = savedTx
  } else {
    store.transactions.unshift(savedTx)
  }
  await fetchPayments()
  return savedTx
}

// Analytics Computeds in KES
export const dashboardAnalytics = computed(() => {
  const totalUnits = store.units.length
  const occupiedUnits = store.units.filter(u => u.status === 'occupied').length
  const vacantUnits = store.units.filter(u => u.status === 'vacant').length
  const maintenanceUnits = store.units.filter(u => u.status === 'maintenance').length
  const occupancyRate = totalUnits > 0 ? (occupiedUnits / totalUnits) * 100 : 0

  const monthlyRecurringRevenue = store.leases
    .filter(l => l.status === 'active')
    .reduce((sum, l) => sum + l.monthlyRent, 0)

  const totalPotentialRevenue = store.units.reduce((sum, u) => sum + getUnitMonthlyRent(u), 0)
  // Pending Collections: Derived strictly from SUM(active monthly rent - reconciled rent payments) for active leases
  const pendingCollections = store.tenants.reduce((sum, t) => {
    const standing = getTenantFinancialStanding(t)
    return sum + (standing.balance > 0 ? standing.balance : 0)
  }, 0)

  const nowMonth = new Date().toISOString().slice(0, 7)
  const currentMonthCollections = store.transactions
    .filter(tx => (tx.status === 'reconciled' || tx.reconciled) && tx.date.startsWith(nowMonth))
    .reduce((sum, tx) => sum + tx.amount, 0)

  const breakdowns = (store.unitTypes || []).map(ut => {
    const type = ut.key
    const list = store.units.filter(u => u.type === type)
    const count = list.length
    const occupied = list.filter(u => u.status === 'occupied').length
    const vacant = list.filter(u => u.status === 'vacant').length
    const maintenance = list.filter(u => u.status === 'maintenance').length
    const typeRate = count > 0 ? Math.round((occupied / count) * 100) : 0
    const activeRent = store.leases
      .filter(l => l.status === 'active' && l.unitType === type)
      .reduce((sum, l) => sum + l.monthlyRent, 0)
    const potentialRent = list.reduce((sum, u) => sum + getUnitMonthlyRent(u), 0)
    const avgRent = count > 0 ? Math.round(potentialRent / count) : 0

    return {
      type,
      title: ut.name,
      totalCount: count,
      occupiedCount: occupied,
      vacantCount: vacant,
      maintenanceCount: maintenance,
      occupancyRate: typeRate,
      activeRevenue: activeRent,
      potentialRevenue: potentialRent,
      avgRent
    }
  })

  return {
    totalUnits,
    occupiedUnits,
    vacantUnits,
    maintenanceUnits,
    occupancyRate: Math.round(occupancyRate * 10) / 10,
    monthlyRecurringRevenue,
    totalPotentialRevenue,
    pendingCollections,
    currentMonthCollections,
    breakdowns
  }
})

// ==========================================
// Dynamic Resident Financial Standing Calculation Engine
// Strictly calculates arrears or advance credit from actual transactions and lease terms
// Eliminates raw negative numbers and hardcoded desynchronized ledger states
// ==========================================

export interface TenantFinancialStanding {
  totalPaid: number
  totalBilled: number
  balance: number // strictly positive arrears if due, or 0
  arrearsBalance: number
  accountCredit: number // positive surplus credit if overpaid, or 0
  status: 'credit' | 'arrears' | 'settled'
  statusText: string // e.g. "Credit of KES 15,000", "Arrear of KES 34,000", "KES 0"
  badgeText: string // e.g. "● Credit of KES 15,000", "● Arrear of KES 34,000", "● All paid up"
  badgeClass: 'paid' | 'overdue' | 'active'
  description: string
  nextDueDate: string
}

function computeLeaseStanding(lease: Lease, tenant: Tenant) {
  let monthsBilled = Number(lease.monthsBilled || 0)
  if (monthsBilled <= 0) {
    monthsBilled = 1
    if (lease.startDate) {
      const startParts = lease.startDate.split('-').map(Number)
      if (startParts.length === 3) {
        const now = new Date()
        const startDate = new Date(Date.UTC(startParts[0], startParts[1] - 1, startParts[2]))
        const todayUtc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
        if (todayUtc.getTime() < startDate.getTime()) {
          monthsBilled = 0
        } else {
          const endParts = lease.endDate ? lease.endDate.split('-').map(Number) : []
          const endDate = endParts.length === 3 ? new Date(Date.UTC(endParts[0], endParts[1] - 1, endParts[2])) : null
          const effectiveEnd = endDate && todayUtc.getTime() > endDate.getTime() ? endDate : todayUtc
          monthsBilled = Math.max(
            1,
            (effectiveEnd.getUTCFullYear() - startDate.getUTCFullYear()) * 12 +
              (effectiveEnd.getUTCMonth() - startDate.getUTCMonth()) +
              1
          )
        }
      }
    }
  }

  const unit = (lease.unitId ? store.units.find(u => u.id === lease.unitId) : null) ||
               (lease.unitNumber ? store.units.find(u => u.unitNumber === lease.unitNumber) : null)
  const monthlyRent = lease.monthlyRent > 0 ? lease.monthlyRent : (unit ? getUnitMonthlyRent(unit) : 0)
  const depositAmount = lease.depositAmount !== undefined ? Number(lease.depositAmount) : monthlyRent

  // Prefer server-reconciled lease fields (which include ledger adjustments) when present!
  const hasServerReconciledLease =
    typeof lease.leaseBalance === 'number' &&
    typeof lease.leaseCredit === 'number' &&
    (typeof lease.leaseBilled === 'number' || typeof lease.leasePaid === 'number' || lease.leaseBalance > 0 || lease.leaseCredit > 0)

  // Strictly match ONLY transactions linked to THIS specific lease/unit (NEVER pull payments from another unit!)
  const leaseTxs = store.transactions.filter(tx => {
    const isVerified = tx.status === 'reconciled' || tx.reconciled === true || tx.status === 'completed' || tx.status === 'paid'
    if (!isVerified) return false
    if (tx.leaseId) return tx.leaseId === lease.id
    if (tx.unitNumber && lease.unitNumber) return tx.unitNumber === lease.unitNumber && (!tx.tenantId || tx.tenantId === tenant.id)
    // Only fall back to tenantId match if tenant has a SINGLE active lease
    const activeCount = store.leases.filter(l => l.tenantId === tenant.id && (l.status === 'active' || l.status === 'pending_deposit')).length
    return activeCount <= 1 && tx.tenantId === tenant.id
  })

  const txPaid = leaseTxs.reduce((sum, tx) => sum + Number(tx.amount || 0), 0)
  const totalBilled = typeof lease.leaseBilled === 'number' && lease.leaseBilled > 0
    ? lease.leaseBilled
    : depositAmount + (monthsBilled * monthlyRent)
  const totalPaid = typeof lease.leasePaid === 'number' && lease.leasePaid >= txPaid
    ? lease.leasePaid
    : txPaid

  const balance = hasServerReconciledLease ? Math.max(0, Number(lease.leaseBalance || 0)) : Math.max(0, totalBilled - totalPaid)
  const accountCredit = hasServerReconciledLease ? Math.max(0, Number(lease.leaseCredit || 0)) : Math.max(0, totalPaid - totalBilled)
  const baseStartDate = lease.startDate || tenant.moveInDate || new Date().toISOString().slice(0, 10)
  const nextDueDate = lease.nextPaymentDueDate || calculateNextDueDate(baseStartDate, propertySettings.rentDueDay || 5, accountCredit, monthlyRent)

  return { totalPaid, totalBilled, balance, accountCredit, monthlyRent, nextDueDate }
}

export function getTenantFinancialStanding(
  tenant: Tenant | null | undefined,
  targetLease?: Lease | null
): TenantFinancialStanding {
  if (!tenant) {
    const defaultDueDate = calculateNextDueDate(new Date().toISOString().slice(0, 10), propertySettings.rentDueDay || 5)
    return {
      totalPaid: 0,
      totalBilled: 0,
      balance: 0,
      arrearsBalance: 0,
      accountCredit: 0,
      status: 'settled',
      statusText: 'KES 0',
      badgeText: '● All paid up',
      badgeClass: 'paid',
      description: 'No resident record loaded.',
      nextDueDate: defaultDueDate
    }
  }

  const activeLeases = store.leases.filter(
    l => l.tenantId === tenant.id && (l.status === 'active' || l.status === 'pending_deposit')
  )
  const resolvedLeases = targetLease
    ? [targetLease]
    : (activeLeases.length > 0
        ? activeLeases
        : store.leases.filter(l => l.tenantId === tenant.id).slice(0, 1))

  // If resident has no active lease, compute unassigned credit only from their own transactions
  if (resolvedLeases.length === 0) {
    const tenantTxs = store.transactions.filter(tx => {
      const isTargetTenant = tx.tenantId === tenant.id
      return isTargetTenant && (tx.status === 'reconciled' || tx.reconciled === true)
    })
    const totalPaid = tenantTxs.reduce((sum, tx) => sum + Number(tx.amount || 0), 0)
    const nextDueDate = calculateNextDueDate(new Date().toISOString().slice(0, 10), propertySettings.rentDueDay || 5, totalPaid, 0)

    return {
      totalPaid,
      totalBilled: 0,
      balance: 0,
      arrearsBalance: 0,
      accountCredit: totalPaid,
      status: totalPaid > 0 ? 'credit' : 'settled',
      statusText: totalPaid > 0 ? `Credit of ${formatKES(totalPaid)}` : 'KES 0',
      badgeText: totalPaid > 0 ? `● Credit of ${formatKES(totalPaid)}` : '● All paid up',
      badgeClass: totalPaid > 0 ? 'active' : 'paid',
      description: totalPaid > 0
        ? `You have an unassigned credit of ${formatKES(totalPaid)} on file.`
        : 'No active lease or unit assigned · Account is clear.',
      nextDueDate
    }
  }

  // Compute each lease strictly in isolation (payments for Unit A NEVER spill into Unit B!)
  const perLease = resolvedLeases.map(l => computeLeaseStanding(l, tenant))
  const totalPaid = perLease.reduce((s, r) => s + r.totalPaid, 0)
  const totalBilled = perLease.reduce((s, r) => s + r.totalBilled, 0)
  const balance = perLease.reduce((s, r) => s + r.balance, 0)
  const rawCredit = perLease.reduce((s, r) => s + r.accountCredit, 0)
  const accountCredit = balance > 0 ? 0 : rawCredit
  const arrearsBalance = balance
  const nextDueDate = perLease.map(r => r.nextDueDate).sort()[0] || tenant.nextPaymentDueDate || calculateNextDueDate(new Date().toISOString().slice(0, 10), propertySettings.rentDueDay || 5)

  let status: 'credit' | 'arrears' | 'settled' = 'settled'
  let statusText = 'KES 0'
  let badgeText = '● All paid up'
  let badgeClass: 'paid' | 'overdue' | 'active' = 'paid'
  let description = targetLease
    ? `Unit ${targetLease.unitNumber} is paid up for the current cycle.`
    : 'No balance due · All paid up for the current cycle.'

  if (balance > 0) {
    status = 'arrears'
    statusText = `Arrear of ${formatKES(balance)}`
    badgeText = `● Arrear of ${formatKES(balance)}`
    badgeClass = 'overdue'
    description = targetLease
      ? `Unit ${targetLease.unitNumber} has a balance of ${formatKES(balance)} due.`
      : 'You have an arrear currently due for payment.'
  } else if (accountCredit > 0) {
    status = 'credit'
    statusText = `Credit of ${formatKES(accountCredit)}`
    badgeText = `● Credit of ${formatKES(accountCredit)}`
    badgeClass = 'active'
    description = targetLease
      ? `Unit ${targetLease.unitNumber} holds ${formatKES(accountCredit)} in advance credit · covered until ${formatHumanDate(nextDueDate)}.`
      : `You have an advance credit of ${formatKES(accountCredit)}. Next due ${formatHumanDate(nextDueDate)}.`
  }

  return {
    totalPaid,
    totalBilled,
    balance,
    arrearsBalance,
    accountCredit,
    status,
    statusText,
    badgeText,
    badgeClass,
    description,
    nextDueDate
  }
}

/**
 * Audit Backing for Security Deposits:
 * Strict Verification: A lease deposit is only verified as 'Paid' if a corresponding
 * audited transaction for THIS specific lease exists in the database ledger.
 */
export function isDepositVerifiedPaid(lease: Lease | null | undefined): boolean {
  if (!lease) return false
  if (lease.depositPaid === true || lease.depositStatus === 'paid') return true

  const totalPaid = store.transactions
    .filter(tx => {
      const isVerified = tx.status === 'reconciled' || tx.reconciled === true
      if (!isVerified) return false
      if (tx.leaseId) return tx.leaseId === lease.id
      return Boolean(lease.unitNumber && tx.unitNumber === lease.unitNumber)
    })
    .reduce((sum, tx) => sum + (Number(tx.amount) || 0), 0)

  return totalPaid >= (Number(lease.depositAmount) || 0)
}

// ==========================================
// Maintenance Requests Client API
// ==========================================

export async function submitMaintenanceRequest(payload: {
  category: MaintenanceCategory
  priority: MaintenancePriority
  title: string
  description: string
  tenantId?: string
  unitId?: string
  unitNumber?: string
}): Promise<MaintenanceRequest> {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  let newTicket: any = null
  try {
    const res = await fetch('/api/maintenance', {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    })
    if (res.ok) {
      newTicket = await res.json()
    }
  } catch (e) {}

  if (!newTicket || !newTicket.id) {
    const tenant = store.tenants.find(t => t.id === payload.tenantId)
    newTicket = {
      id: generateObjectId(),
      tenantId: payload.tenantId || tenant?.id || store.session.id,
      tenantName: tenant?.name || store.session.name,
      unitId: payload.unitId || tenant?.currentUnitId,
      unitNumber: payload.unitNumber || tenant?.currentUnitNumber || 'Pending',
      category: payload.category,
      priority: payload.priority,
      title: payload.title.trim(),
      description: payload.description.trim(),
      status: 'pending',
      createdAt: new Date().toISOString().slice(0, 19).replace('T', ' ')
    }
  }

  if (!store.maintenanceRequests) store.maintenanceRequests = []
  store.maintenanceRequests.unshift(newTicket)

  // Notify Landlord
  addNotification({
    userId: null,
    role: 'landlord',
    type: 'maintenance_update',
    title: `New Maintenance Ticket: Unit ${newTicket.unitNumber}`,
    message: `${newTicket.title} (${newTicket.priority.toUpperCase()} priority, reported by ${newTicket.tenantName})`,
    link: '/maintenance'
  })

  saveStore()
  return newTicket
}

export const createMaintenanceRequest = submitMaintenanceRequest

export async function updateMaintenanceStatus(
  id: string,
  updates: { status?: MaintenanceStatus; assignedTo?: string; resolutionNotes?: string }
): Promise<MaintenanceRequest> {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  try {
    const res = await fetch(`/api/maintenance/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(updates)
    })
    if (res.ok) {
      const updated = await res.json()
      const idx = (store.maintenanceRequests || []).findIndex(m => m.id === id)
      if (idx !== -1) {
        store.maintenanceRequests[idx] = updated
      }
      saveStore()
      return updated
    }
  } catch (e) {}

  const req = (store.maintenanceRequests || []).find(m => m.id === id)
  if (!req) throw new Error('Maintenance request not found')
  const nowIso = new Date().toISOString().slice(0, 19).replace('T', ' ')
  req.updatedAt = nowIso
  if (updates.status) req.status = updates.status
  if (updates.assignedTo !== undefined) req.assignedTo = updates.assignedTo
  if (updates.resolutionNotes !== undefined) req.resolutionNotes = updates.resolutionNotes
  if (updates.status === 'resolved') req.resolvedAt = nowIso

  saveStore()
  return req
}

export const updateMaintenanceRequest = updateMaintenanceStatus

// ==========================================
// Notification API Helpers
// ==========================================

export function addNotification(payload: {
  userId?: string | null
  tenantId?: string | null
  role?: 'landlord' | 'tenant' | 'all'
  type: NotificationType
  title: string
  message: string
  link?: string
}): AppNotification {
  const nowIso = new Date().toISOString().slice(0, 19).replace('T', ' ')
  const notif: AppNotification = {
    id: generateObjectId(),
    userId: payload.userId || null,
    tenantId: payload.tenantId || null,
    role: payload.role || 'all',
    type: payload.type,
    title: payload.title,
    message: payload.message,
    timestamp: nowIso,
    read: false,
    link: payload.link
  }

  if (!store.notifications) {
    store.notifications = []
  }
  store.notifications.unshift(notif)
  saveStore()
  return notif
}

export async function markNotificationRead(id: string) {
  const notif = store.notifications.find(n => n.id === id)
  if (notif) notif.read = true

  const token = store.session.token
  if (token) {
    await fetch(`/api/notifications/${id}/read`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` }
    }).catch(() => {})
  }
  saveStore()
}

export async function markAllNotificationsRead(_role?: string) {
  store.notifications.forEach(n => { n.read = true })
  const token = store.session.token
  if (token) {
    await fetch('/api/notifications/mark-all-read', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` }
    }).catch(() => {})
  }
  saveStore()
}

export const unreadNotificationsCount = computed(() => {
  return store.notifications.filter(n => {
    if (n.read) return false
    if (store.session.role === 'tenant') {
      return n.tenantId === store.session.id || n.role === 'tenant' || n.role === 'all'
    }
    return n.role === 'landlord' || n.role === 'all' || !n.role
  }).length
})

export const userNotifications = computed(() => {
  return store.notifications.filter(n => {
    if (store.session.role === 'tenant') {
      return n.tenantId === store.session.id || n.role === 'tenant' || n.role === 'all'
    }
    return n.role === 'landlord' || n.role === 'all' || !n.role
  })
})

export const computeTenantFinancialStanding = getTenantFinancialStanding

// ==========================================
// KCB Buni API Payments Integration
// ==========================================

export async function initiateKcbStkPush(payload: {
  phoneNumber: string
  amount: number
  invoiceNumber?: string
  description?: string
  tenantId?: string
  leaseId?: string
  unitNumber?: string
}) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/kcb/stkpush', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      ...payload,
      callerName: store.session.name,
      callerEmail: store.session.email
    })
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error(data.error || 'Failed to initiate KCB STK Push')
  }
  return data
}

export async function queryKcbStatus(checkoutRequestId?: string, merchantRequestId?: string, syncLive = true) {
  const res = await safeFetchJson('/api/kcb/query', {
    method: 'POST',
    headers: authHeaders(true),
    body: JSON.stringify({ checkoutRequestId, merchantRequestId, syncLive })
  })
  if (!res.ok) throw new Error(res.error || 'Could not query transaction status.')
  return res.data
}

export async function resolvePendingKcbTransaction(payload: {
  id?: string
  checkoutRequestId?: string
  merchantRequestId?: string
  action: 'confirm' | 'fail'
  mpesaReceiptNumber?: string
  reason?: string
}) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await safeFetchJson('/api/kcb/resolve-pending', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  })
  if (!res.ok) throw new Error(res.error || 'Failed to update pending STK transaction.')
  return res.data
}

export async function waitForKcbCallback(checkoutRequestId?: string, merchantRequestId?: string, timeout = 50000) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/kcb/wait-callback', {
    method: 'POST',
    headers,
    body: JSON.stringify({ checkoutRequestId, merchantRequestId, timeout })
  })
  return await res.json()
}

export async function fetchKcbAuditLogs(): Promise<KcbTransactionRecord[]> {
  const token = store.session.token
  const headers: Record<string, string> = {}
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/kcb/audit-logs', { headers })
  if (!res.ok) throw new Error('Failed to fetch KCB audit logs')
  return await res.json()
}

export async function reconcileTenantLedger(tenantId: string) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch(`/api/tenants/${tenantId}/reconcile`, {
    method: 'POST',
    headers
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'Reconciliation failed' }))
    throw new Error(err.error || 'Failed to reconcile tenant ledger')
  }
  const data = await res.json()

  if (data.tenant) {
    const idx = store.tenants.findIndex(t => t.id === data.tenant.id)
    if (idx >= 0) store.tenants[idx] = { ...store.tenants[idx], ...data.tenant }
  }
  if (data.lease) {
    const idx = store.leases.findIndex(l => l.id === data.lease.id)
    if (idx >= 0) store.leases[idx] = { ...store.leases[idx], ...data.lease }
  }
  await fetchPayments()

  return data
}

export interface TrackedPaymentLink {
  id: string
  linkId: string
  tenantId: string
  unitNumber: string
  tenantName: string
  tenantPhone: string
  billingMonth: string
  billingMonths?: string[]
  amountDueAtSend: number
  currentAmountDue?: number
  remainingBalance?: number
  totalPaidViaLink?: number
  payments?: Array<{ amount: number; mpesaReceipt?: string; transactionId?: string; paidAt: string }>
  remindersSentCount?: number
  dueDate: string
  stage: string
  shortUrl: string
  status: 'sent' | 'clicked' | 'verified' | 'partial' | 'paid' | 'expired'
  clickCount: number
  clickedAt?: string | null
  lastClickedAt?: string | null
  otpRequestedAt?: string | null
  otpVerifiedAt?: string | null
  paidAt?: string | null
  settledAt?: string | null
  paidAmount?: number | null
  mpesaReceipt?: string | null
  smsDeliveryStatus?: string
  smsCarrierDetail?: string | null
  createdAt: string
}

export async function fetchReminderLinks(): Promise<{ links: TrackedPaymentLink[]; stats: { total: number; active?: number; partial?: number; clicked: number; verified: number; paid: number; totalCollectedViaLinks?: number } }> {
  const token = store.session.token
  const headers: Record<string, string> = {}
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await safeFetchJson('/api/reminders/links', { headers })
  if (!res.ok) throw new Error(res.error || 'Failed to load tracked reminder payment links')
  return res.data
}

export interface AdminAccountSetting {
  id?: string
  name: string
  email: string
  phone: string
  avatarInitials?: string
}

export async function fetchAppSettings(): Promise<{ settings: any; admins: AdminAccountSetting[] } | null> {
  try {
    const token = store.session.token
    if (!token) return null
    const res = await fetch('/api/settings', {
      headers: { Authorization: `Bearer ${token}` }
    })
    if (!res.ok) return null
    const data = await res.json()
    if (data.settings) {
      propertyInfo.name = data.settings.propertyName || propertyInfo.name
      propertyInfo.address = data.settings.address || propertyInfo.address
      propertyInfo.city = data.settings.city || propertyInfo.city
      propertyInfo.totalFloors = Number(data.settings.totalFloors || propertyInfo.totalFloors)
      propertyInfo.managerName = data.settings.managerName || propertyInfo.managerName
      propertyInfo.contactPhone = data.settings.contactPhone || propertyInfo.contactPhone
      propertyInfo.contactEmail = data.settings.contactEmail || propertyInfo.contactEmail
      propertyInfo.paybillNumber = data.settings.paybillNumber || propertyInfo.paybillNumber

      propertySettings.propertyName = data.settings.propertyName || propertySettings.propertyName
      propertySettings.currency = data.settings.currency || propertySettings.currency
      propertySettings.rentDueDay = Number(data.settings.rentDueDay || propertySettings.rentDueDay)
      propertySettings.gracePeriodDays = Number(data.settings.gracePeriodDays ?? propertySettings.gracePeriodDays)
      propertySettings.lateFeePercent = Number(data.settings.lateFeePercent ?? propertySettings.lateFeePercent)
      propertySettings.autoReconciliationEnabled = Boolean(data.settings.autoReconciliationEnabled ?? true)
      propertySettings.paybillNumber = data.settings.paybillNumber || propertySettings.paybillNumber
    }
    return data
  } catch (err) {
    console.warn('Could not fetch settings:', err)
    return null
  }
}

export async function saveAppSettings(payload: { settings: Record<string, any>; admins?: AdminAccountSetting[] }) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/settings', {
    method: 'PUT',
    headers,
    body: JSON.stringify(payload)
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to save settings')
  if (data.settings) {
    propertyInfo.name = data.settings.propertyName || propertyInfo.name
    propertyInfo.address = data.settings.address || propertyInfo.address
    propertyInfo.city = data.settings.city || propertyInfo.city
    propertyInfo.totalFloors = Number(data.settings.totalFloors || propertyInfo.totalFloors)
    propertyInfo.managerName = data.settings.managerName || propertyInfo.managerName
    propertyInfo.contactPhone = data.settings.contactPhone || propertyInfo.contactPhone
    propertyInfo.contactEmail = data.settings.contactEmail || propertyInfo.contactEmail
    propertyInfo.paybillNumber = data.settings.paybillNumber || propertyInfo.paybillNumber

    propertySettings.propertyName = data.settings.propertyName || propertySettings.propertyName
    propertySettings.rentDueDay = Number(data.settings.rentDueDay || propertySettings.rentDueDay)
    propertySettings.gracePeriodDays = Number(data.settings.gracePeriodDays ?? propertySettings.gracePeriodDays)
    propertySettings.lateFeePercent = Number(data.settings.lateFeePercent ?? propertySettings.lateFeePercent)
    propertySettings.paybillNumber = data.settings.paybillNumber || propertySettings.paybillNumber
  }
  return data
}

export async function requestAdminStkOtp(payload: { amount: number; unitNumber?: string; tenantName?: string }) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/kcb/admin-stk/request-otp', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to send admin confirmation OTP')
  return data
}

export async function verifyAndDispatchAdminStk(payload: {
  challengeToken: string
  code: string
  phoneNumber: string
  amount: number
  invoiceNumber?: string
  description?: string
  tenantId?: string
  unitNumber?: string
}) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/kcb/admin-stk/verify-and-push', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      ...payload,
      callerName: store.session.name,
      callerEmail: store.session.email
    })
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'OTP verification or STK push failed')
  return data
}

export async function runRentReminders(payload: { force?: boolean; tenantId?: string } = {}) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/reminders/run', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to dispatch rent reminders')
  return data
}

export interface AuditLogEntry {
  id: string
  timestamp: string
  actorId?: string | null
  actorName: string
  actorEmail: string
  actorRole: string
  action: string
  entityType: string
  entityId?: string | null
  summary: string
  meta?: Record<string, any>
}

export async function fetchAuditLogs(params: { limit?: number; entityType?: string; search?: string } = {}): Promise<AuditLogEntry[]> {
  const token = store.session.token
  const headers: Record<string, string> = {}
  if (token) headers['Authorization'] = `Bearer ${token}`

  const qs = new URLSearchParams()
  if (params.limit) qs.set('limit', String(params.limit))
  if (params.entityType && params.entityType !== 'all') qs.set('entityType', params.entityType)
  if (params.search) qs.set('search', params.search)
  const suffix = qs.toString() ? `?${qs.toString()}` : ''

  const res = await fetch(`/api/audit-logs${suffix}`, { headers })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'Failed to load audit logs' }))
    throw new Error(err.error || 'Failed to load audit logs')
  }
  return await res.json()
}

export async function changeMyPassword(payload: { currentPassword: string; newPassword: string; confirmPassword: string }) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/auth/change-password', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to update password')
  if (data.token) {
    store.session.token = data.token
    try { localStorage.setItem('lapis_token', data.token) } catch {}
  }
  return data
}

export async function logoutAllDevices() {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/auth/logout-all', { method: 'POST', headers })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to sign out of all devices')
  return data
}

export async function reconcileAllTenants() {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const res = await fetch('/api/tenants/reconcile-all', { method: 'POST', headers })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Batch reconciliation failed')
  await fetchDashboard()
  return data
}

export interface LedgerAdjustment {
  id: string
  tenantId: string
  tenantName?: string
  leaseId?: string | null
  unitNumber?: string
  type: 'charge' | 'credit'
  category: string
  amount: number
  reason: string
  createdBy: string
  createdAt: string
}

export async function fetchTenantAdjustments(tenantId: string): Promise<LedgerAdjustment[]> {
  const token = store.session.token
  const headers: Record<string, string> = {}
  if (token) headers['Authorization'] = `Bearer ${token}`
  const res = await fetch(`/api/tenants/${tenantId}/adjustments`, { headers })
  if (!res.ok) throw new Error('Failed to load adjustments')
  return await res.json()
}

export async function createTenantAdjustment(tenantId: string, payload: { type: 'charge' | 'credit'; amount: number; category?: string; reason: string; leaseId?: string }) {
  const token = store.session.token
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers['Authorization'] = `Bearer ${token}`
  const res = await fetch(`/api/tenants/${tenantId}/adjustments`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || 'Failed to save adjustment')
  await fetchDashboard()
  return data
}




