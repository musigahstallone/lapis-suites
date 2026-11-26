// Strict TypeScript Definitions for Lapis Suites Property Management
// Uses MongoDB BSON-style 24-character hexadecimal ObjectId strings across all entities

export type UnitType = string
export type UnitStatus = 'occupied' | 'vacant' | 'maintenance'

export interface UnitTypeConfig {
  id: string // 24-char hex ObjectId
  key: UnitType
  name: string
  baseRent: number // in KES
  depositMultiplier: number // e.g. 1.0 = one month rent
  description: string
  features: string[] // Centrally managed features and amenities inherited by units
}

export interface Unit {
  id: string // 24-char hex ObjectId
  unitNumber: string // Unit identifier e.g. "S101", "B201" (Immutable once created)
  type: UnitType // Unit type reference
  status: UnitStatus // 'occupied' | 'vacant' | 'maintenance' (Strictly derived from active lease state)
  currentTenantId: string | null
  currentLeaseId?: string | null
}

export type TenantStatus = 'active' | 'transferring' | 'past'

export interface Tenant {
  id: string // 24-char hex ObjectId
  name: string
  email: string
  phone: string
  currentUnitId: string | null
  currentUnitNumber: string
  currentLeaseId: string | null
  avatarInitials: string
  balance: number // in KES (positive = arrears owed; negative = credit balance)
  accountCredit: number // in KES (advance rent credit)
  arrearsBalance: number // in KES (overdue rent)
  nextPaymentDueDate: string // Dynamically calculated by the automated lease billing engine
  status: TenantStatus
  moveInDate: string
  nationalId?: string
  emergencyContact?: string
  otherPhone?: string
}

export type LeaseStatus = 'active' | 'pending_deposit' | 'transferred' | 'terminated' | 'pending'

export interface Lease {
  id: string // 24-char hex ObjectId
  leaseNumber: string // Immutable identifier
  tenantId: string
  tenantName: string
  unitId: string
  unitNumber: string
  unitType: UnitType
  startDate: string
  endDate: string
  monthlyRent: number // in KES
  depositAmount: number // in KES
  depositPaid: boolean // Rule: A lease is ONLY active if the deposit has been made
  firstMonthRent: number // in KES
  totalMoveInRequired: number // in KES
  status: LeaseStatus
  nextPaymentDueDate: string
  terms: string
  phone?: string
  depositStatus?: string
  transferNotes?: string
  transferredToUnitId?: string
  transferredToUnitNumber?: string
}

export type PaymentMethod = 'mpesa_paybill' | 'stk_push' | 'bank_transfer' | 'card'
export type PaymentStatus = 'reconciled' | 'pending' | 'pending_verification' | 'flagged_hold' | 'completed' | 'paid'
export type PaymentCategory = 'rent' | 'deposit' | 'utility' | 'parking' | 'transfer_fee'

export interface LedgerAllocation {
  arrearsPaid: number
  rentPaid: number
  creditBalance: number
  firstMonthRentPaid?: number
  depositPaid?: number
}

// Modeled after KCB / M-Pesa Daraja C2B / STK Webhook Callbacks
export interface DarajaCallbackPayload {
  TransactionType: string
  TransID: string
  TransTime: string
  TransAmount: number
  BusinessShortCode: string
  BillRefNumber: string
  InvoiceNumber?: string
  OrgAccountBalance?: string
  MSISDN: string
  FirstName: string
  LastName: string
}

export interface Transaction {
  id: string // 24-char hex ObjectId (Immutable once recorded)
  reference: string // TransID (e.g. DAR9X18K02)
  invoiceRef: string
  tenantId: string | null // Mapped tenant ObjectId or null if unassigned
  tenantName: string
  unitId: string | null // Mapped unit ObjectId or null if unassigned
  unitNumber: string // Mapped unit name/number
  leaseId: string | null
  amount: number // in KES (Immutable once recorded)
  date: string // YYYY-MM-DD
  timestamp: string // Formatted ISO or Daraja time
  method: PaymentMethod
  status: PaymentStatus // 'reconciled' | 'pending' | 'flagged_hold'
  category: PaymentCategory
  phoneNumber: string // MSISDN (e.g. 254712904883)
  payerName?: string
  billRefNumber?: string // Account number provided by payer
  notes: string
  reconciled: boolean
  reconciledAt?: string
  reconciledBy?: string
  allocation?: LedgerAllocation
  rawCallback?: DarajaCallbackPayload // Clean raw callback payload
  source?: string
  paymentType?: string
}

export interface UnitTransferPayload {
  tenantId: string
  currentUnitId: string
  newUnitId: string
  transferDate: string
  newRent: number
  depositRollOver: boolean
  transferFee: number
  transferNotes: string
}

export interface PropertySettings {
  propertyName: string
  currency: string
  rentDueDay: number // Day of month when rent is due (e.g. 5 for the 5th)
  gracePeriodDays: number
  lateFeePercent: number
  autoReconciliationEnabled: boolean
  paybillNumber: string
}

// Maintenance Requests Module
export type MaintenanceCategory = 'plumbing' | 'electrical' | 'carpentry' | 'hvac' | 'appliance' | 'internet' | 'general'
export type MaintenancePriority = 'low' | 'medium' | 'high' | 'emergency'
export type MaintenanceStatus = 'pending' | 'in_progress' | 'resolved' | 'cancelled'

export interface MaintenanceRequest {
  id: string // 24-char hex ObjectId
  tenantId: string
  tenantName: string
  unitId?: string | null
  unitNumber: string
  category: MaintenanceCategory
  priority: MaintenancePriority
  title: string
  description: string
  status: MaintenanceStatus
  createdAt: string
  updatedAt?: string
  resolvedAt?: string
  assignedTo?: string // Technician name or service provider
  resolutionNotes?: string
}

// Real-Time In-App Notification System
export type NotificationType = 'payment_received' | 'maintenance_update' | 'lease_notice' | 'general'

export interface AppNotification {
  id: string // 24-char hex ObjectId
  userId?: string | null // Target user ObjectId or null for broadcast
  tenantId?: string | null
  role?: 'landlord' | 'tenant' | 'all'
  type: NotificationType
  title: string
  message: string
  timestamp: string
  read: boolean
  link?: string
}

// KCB Buni API Payments Audit Log Record
export interface KcbTransactionRecord {
  id: string // 24-char hex ObjectId
  merchantRequestId: string
  checkoutRequestId?: string
  phoneNumber: string
  amount: number
  invoiceNumber: string
  status: 'Pending' | 'Success' | 'Failed'
  statusCode?: string
  statusDescription?: string
  resultCode?: number
  resultDesc?: string
  mpesaReceiptNumber?: string
  callerName?: string
  callerEmail?: string
  callerRole?: string
  callerIp?: string
  createdAt: string
  updatedAt?: string
  rawResponse?: any
  rawCallback?: any
}
