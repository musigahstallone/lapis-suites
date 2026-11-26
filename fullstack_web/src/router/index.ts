import { createRouter, createWebHashHistory } from 'vue-router'
import { store } from '../data'

// Auth & Public Express Views
import LoginView from '../views/auth/LoginView.vue'
import RegisterView from '../views/auth/RegisterView.vue'
import ForgotPasswordView from '../views/auth/ForgotPasswordView.vue'
import VerifyCodeView from '../views/auth/VerifyCodeView.vue'
import ResetPasswordView from '../views/auth/ResetPasswordView.vue'
import PublicPayView from '../views/PublicPayView.vue'

// Landlord Views
import DashboardView from '../views/DashboardView.vue'
import UnitsView from '../views/UnitsView.vue'
import UnitDetailsView from '../views/UnitDetailsView.vue'
import UnitLeaseView from '../views/UnitLeaseView.vue'
import TenantsView from '../views/TenantsView.vue'
import TenantDetailsView from '../views/TenantDetailsView.vue'
import TenantLeaseChangesView from '../views/TenantLeaseChangesView.vue'
import LeasesView from '../views/LeasesView.vue'
import LeaseDetailsView from '../views/LeaseDetailsView.vue'
import LeaseChangesView from '../views/LeaseChangesView.vue'
import PaymentsView from '../views/PaymentsView.vue'
import RecordPaymentView from '../views/RecordPaymentView.vue'
import ReconciliationView from '../views/ReconciliationView.vue'
import AuditLogView from '../views/AuditLogView.vue'
import MaintenanceView from '../views/MaintenanceView.vue'
import SettingsView from '../views/SettingsView.vue'

// Tenant Views
import TenantHomeView from '../views/tenant/TenantHomeView.vue'
import TenantPaymentsView from '../views/tenant/TenantPaymentsView.vue'
import TenantPayView from '../views/tenant/TenantPayView.vue'
import TenantMaintenanceView from '../views/tenant/TenantMaintenanceView.vue'
import TenantDocumentsView from '../views/tenant/TenantDocumentsView.vue'
import TenantSettingsView from '../views/tenant/TenantSettingsView.vue'

const routes = [
  // Auth
  { path: '/login', name: 'login', component: LoginView, meta: { public: true } },
  { path: '/register', name: 'register', component: RegisterView, meta: { public: true } },
  { path: '/forgot-password', name: 'forgot-password', component: ForgotPasswordView, meta: { public: true } },
  { path: '/verify-code', name: 'verify-code', component: VerifyCodeView, meta: { public: true } },
  { path: '/reset-password', name: 'reset-password', component: ResetPasswordView, meta: { public: true } },

  // Landlord Portal
  { path: '/dashboard', name: 'dashboard', component: DashboardView, meta: { role: 'landlord', title: 'Dashboard' } },
  { path: '/units', name: 'units', component: UnitsView, meta: { role: 'landlord', title: 'Units' } },
  { path: '/units/:id', name: 'unit-details', component: UnitDetailsView, meta: { role: 'landlord', title: 'Unit Details' } },
  { path: '/units/:id/lease', name: 'unit-lease', component: UnitLeaseView, meta: { role: 'landlord', title: 'Unit Lease' } },
  { path: '/tenants', name: 'tenants', component: TenantsView, meta: { role: 'landlord', title: 'Tenants' } },
  { path: '/tenants/:id', name: 'tenant-details', component: TenantDetailsView, meta: { role: 'landlord', title: 'Tenant Details' } },
  { path: '/tenants/:id/lease-changes', name: 'tenant-lease-changes', component: TenantLeaseChangesView, meta: { role: 'landlord', title: 'Lease Changes' } },
  { path: '/leases', name: 'leases', component: LeasesView, meta: { role: 'landlord', title: 'Leases' } },
  { path: '/leases/changes', name: 'lease-changes', component: LeaseChangesView, meta: { role: 'landlord', title: 'Lease Changes' } },
  { path: '/leases/:id', name: 'lease-details', component: LeaseDetailsView, meta: { role: 'landlord', title: 'Lease Details' } },
  { path: '/payments', name: 'payments', component: PaymentsView, meta: { role: 'landlord', title: 'Rent Payments' } },
  { path: '/payments/record', name: 'payments-record', component: RecordPaymentView, meta: { role: 'landlord', title: 'Record Payment' } },
  { path: '/reconciliation', name: 'reconciliation', component: ReconciliationView, meta: { role: 'landlord', title: 'Reconciliation' } },
  { path: '/audit', name: 'audit-reflections', component: AuditLogView, meta: { role: 'landlord', title: 'Audit Log' } },
  { path: '/maintenance', name: 'maintenance', component: MaintenanceView, meta: { role: 'landlord', title: 'Maintenance' } },
  { path: '/settings', name: 'settings', component: SettingsView, meta: { role: 'landlord', title: 'Settings' } },

  // Tenant Portal
  { path: '/tenant/home', name: 'tenant-home', component: TenantHomeView, meta: { role: 'tenant', title: 'Home' } },
  { path: '/tenant/payments', name: 'tenant-payments', component: TenantPaymentsView, meta: { role: 'tenant', title: 'Rent Payments' } },
  { path: '/tenant/pay', name: 'tenant-pay', component: TenantPayView, meta: { role: 'tenant', title: 'Pay Rent' } },
  { path: '/pay', name: 'public-pay', component: PublicPayView, meta: { public: true, allowAuthenticated: true, title: 'Pay Rent' } },
  { path: '/pay/:linkId', name: 'public-pay-link', component: PublicPayView, meta: { public: true, allowAuthenticated: true, title: 'Pay Rent' } },
  { path: '/tenant/maintenance', name: 'tenant-maintenance', component: TenantMaintenanceView, meta: { role: 'tenant', title: 'Maintenance' } },
  { path: '/tenant/documents', name: 'tenant-documents', component: TenantDocumentsView, meta: { role: 'tenant', title: 'Documents' } },
  { path: '/tenant/settings', name: 'tenant-settings', component: TenantSettingsView, meta: { role: 'tenant', title: 'Settings' } },

  // Fallback / root redirect
  {
    path: '/:pathMatch(.*)*',
    redirect: () => {
      if (!store.session.isAuthenticated) return '/login'
      return store.session.role === 'landlord' ? '/dashboard' : '/tenant/home'
    }
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to, from, next) => {
  const isPublic = to.meta.public === true
  const isAuthenticated = store.session.isAuthenticated

  if (!isAuthenticated && !isPublic) {
    return next('/login')
  }

  if (isAuthenticated && isPublic && !to.meta.allowAuthenticated) {
    return next(store.session.role === 'landlord' ? '/dashboard' : '/tenant/home')
  }

  if (isAuthenticated && to.meta.role && !to.meta.allowAuthenticated && to.meta.role !== store.session.role) {
    return next(store.session.role === 'landlord' ? '/dashboard' : '/tenant/home')
  }

  next()
})

router.afterEach((to) => {
  const title = to.meta?.title as string | undefined
  document.title = title ? `${title} · Lapis Suites` : 'Lapis Suites'
})

export default router
