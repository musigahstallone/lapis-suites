<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, CreditCard, CheckCircle2, Smartphone, RefreshCw, AlertCircle, ShieldCheck } from 'lucide-vue-next'
import {
  store,
  propertySettings,
  processDirectPayment,
  formatKES,
  getTenantFinancialStanding,
  initiateKcbStkPush,
  queryKcbStatus,
  normalizePhone,
  fetchTenantProfile,
  formatHumanDate,
  fetchFromBackend
} from '../../data'
import { onKcbCallback, onPaymentReceived } from '../../sse'
import PhoneInput from '../../components/PhoneInput.vue'

const router = useRouter()

let unsubSseCallback: (() => void) | null = null
let unsubSsePayment: (() => void) | null = null

onMounted(async () => {
  await fetchTenantProfile()

  unsubSseCallback = onKcbCallback((data) => {
    const isTarget =
      data.checkoutRequestId === stkCheckoutRequestId.value ||
      data.merchantRequestId === stkMerchantRequestId.value ||
      (data.callback?.parsed?.checkoutRequestId === stkCheckoutRequestId.value) ||
      (data.callback?.parsed?.phoneNumber === phoneNumber.value)

    if (isTarget) {
      const isSuccess = data.status === 'Success' || data.callback?.parsed?.isSuccess
      if (isSuccess) {
        isAwaitingPin.value = false
        successMessage.value = `Payment of ${formatKES(amount.value)} confirmed via M-Pesa! Receipt: ${data.callback?.parsed?.mpesaReceiptNumber || data.mpesaReceiptNumber || 'Confirmed'}.`
        fetchFromBackend()
        setTimeout(() => {
          router.push('/tenant/payments')
        }, 1800)
      } else {
        isAwaitingPin.value = false
        error.value = `Transaction declined: ${data.resultDesc || data.callback?.parsed?.resultDesc || 'Payment cancelled by user.'}`
      }
    }
  })

  unsubSsePayment = onPaymentReceived((data) => {
    if (data.transaction && (data.transaction.phoneNumber === phoneNumber.value || data.transaction.unitNumber === currentUnit.value?.unitNumber)) {
      isAwaitingPin.value = false
      successMessage.value = `Payment of ${formatKES(data.transaction.amount)} received via M-Pesa! Receipt: ${data.transaction.reference}.`
      fetchFromBackend()
      setTimeout(() => {
        router.push('/tenant/payments')
      }, 1800)
    }
  })
})

onUnmounted(() => {
  if (unsubSseCallback) unsubSseCallback()
  if (unsubSsePayment) unsubSsePayment()
})

const currentTenant = computed(() => {
  return (
    store.tenants.find(t => t.id === store.session.tenantId || t.id === store.session.id) ||
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants[0]
  )
})

const activeLease = computed(() => {
  if (!currentTenant.value) return null
  return (
    store.leases.find(l => (l.tenantId === currentTenant.value?.id || l.tenantName?.toLowerCase() === currentTenant.value?.name?.toLowerCase()) && (l.status === 'active' || l.status === 'pending_deposit')) ||
    store.leases.find(l => (currentTenant.value?.currentUnitNumber && l.unitNumber === currentTenant.value?.currentUnitNumber)) ||
    store.leases.find(l => l.tenantId === currentTenant.value?.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!currentTenant.value) return null
  if (currentTenant.value.currentUnitId) {
    const u = store.units.find(u => u.id === currentTenant.value?.currentUnitId)
    if (u) return u
  }
  if (activeLease.value?.unitId) {
    const u = store.units.find(u => u.id === activeLease.value?.unitId)
    if (u) return u
  }
  const unitNum = currentTenant.value.currentUnitNumber || activeLease.value?.unitNumber || store.session.unitNumber
  if (unitNum) {
    const u = store.units.find(u => u.unitNumber === unitNum)
    if (u) return u
  }
  return null
})

const standing = computed(() => {
  return getTenantFinancialStanding(currentTenant.value)
})

const isDepositUnpaid = computed(() => {
  return activeLease.value && !activeLease.value.depositPaid
})

const paymentMode = ref<'kcb_stk' | 'direct_portal'>('kcb_stk')
const amount = ref<number>(
  standing.value.balance > 0
    ? standing.value.balance
    : (activeLease.value?.monthlyRent || currentUnit.value?.monthlyRent || 0)
)
const phoneNumber = ref(currentTenant.value?.phone || '0712904883')
const reference = ref('')
const notes = ref(isDepositUnpaid.value ? 'Security Deposit & Rent' : 'Monthly Rent Payment')

// Update defaults when resident/unit loads
watch([currentTenant, currentUnit, activeLease], () => {
  if (currentTenant.value?.phone && !phoneNumber.value) {
    phoneNumber.value = currentTenant.value.phone
  }
  if (amount.value === 0) {
    amount.value = standing.value.balance > 0 ? standing.value.balance : (activeLease.value?.monthlyRent || currentUnit.value?.monthlyRent || 0)
  }
  if (isDepositUnpaid.value && (!notes.value || notes.value === 'Monthly Rent Payment')) {
    notes.value = 'Security Deposit & Rent'
  }
})

const isSubmitting = ref(false)
const error = ref('')
const successMessage = ref('')

// STK Push State
const isAwaitingPin = ref(false)
const isCheckingStatus = ref(false)
const stkCheckoutRequestId = ref('')
const stkMerchantRequestId = ref('')
const stkStatusText = ref('')

async function handleKcbStkPush() {
  const effectiveUnit = currentUnit.value?.unitNumber || activeLease.value?.unitNumber || currentTenant.value?.currentUnitNumber || 'Suite'
  if (!currentTenant.value) {
    error.value = 'Resident profile not found.'
    return
  }
  if (!amount.value || amount.value <= 0) {
    error.value = 'Please enter a valid amount.'
    return
  }
  if (!phoneNumber.value || phoneNumber.value.length < 9) {
    error.value = 'Please provide a valid Safaricom phone number.'
    return
  }

  error.value = ''
  successMessage.value = ''
  isSubmitting.value = true
  stkStatusText.value = 'Sending prompt to your phone...'

  try {
    const res = await initiateKcbStkPush({
      phoneNumber: phoneNumber.value,
      amount: Number(amount.value),
      invoiceNumber: `LAPIS-${effectiveUnit}`,
      description: notes.value,
      tenantId: currentTenant.value.id,
      unitNumber: effectiveUnit
    })

    stkCheckoutRequestId.value = res.checkoutRequestId
    stkMerchantRequestId.value = res.merchantRequestId
    isAwaitingPin.value = true
    isSubmitting.value = false
    stkStatusText.value = `Prompt sent to ${res.phoneNumber || phoneNumber.value}. Please enter your M-Pesa PIN to complete payment.`
  } catch (err: any) {
    isSubmitting.value = false
    isAwaitingPin.value = false
    error.value = err.message || 'Failed to dispatch M-Pesa prompt.'
  }
}

async function handleCheckStatusNow() {
  if (!stkCheckoutRequestId.value && !stkMerchantRequestId.value) return
  isCheckingStatus.value = true
  error.value = ''
  try {
    const queryRes = await queryKcbStatus(stkCheckoutRequestId.value, stkMerchantRequestId.value)
    if (queryRes.status === 'Success') {
      isAwaitingPin.value = false
      successMessage.value = `Payment of ${formatKES(amount.value)} confirmed via M-Pesa! Reference: ${queryRes.mpesaReceiptNumber || 'Confirmed'}.`
      await fetchFromBackend()
      setTimeout(() => {
        router.push('/tenant/payments')
      }, 1800)
    } else if (queryRes.status === 'Failed') {
      isAwaitingPin.value = false
      error.value = `Transaction declined: ${queryRes.statusDescription || queryRes.resultDesc || 'Cancelled by user.'}`
    } else {
      stkStatusText.value = 'Status is pending. If you have entered your PIN, please wait a few seconds.'
    }
  } catch (err: any) {
    error.value = `Could not verify status: ${err.message || 'Network error'}`
  } finally {
    isCheckingStatus.value = false
  }
}

async function handleDirectPay() {
  const effectiveUnit = currentUnit.value?.unitNumber || activeLease.value?.unitNumber || currentTenant.value?.currentUnitNumber || 'Suite'
  if (!currentTenant.value) {
    error.value = 'Resident profile not found.'
    return
  }
  if (!amount.value || Number(amount.value) <= 0) {
    error.value = 'Please enter a valid payment amount.'
    return
  }
  const cleanRef = reference.value.trim().toUpperCase()
  if (cleanRef.length < 5) {
    error.value = 'Please enter a valid M-Pesa transaction code (from your confirmation SMS).'
    return
  }

  error.value = ''
  successMessage.value = ''
  isSubmitting.value = true

  try {
    const saved = await processDirectPayment({
      tenantId: currentTenant.value.id,
      unitId: currentUnit.value?.id || activeLease.value?.unitId || undefined,
      leaseId: activeLease.value?.id || undefined,
      amount: Number(amount.value),
      method: 'mpesa_paybill',
      reference: cleanRef,
      notes: notes.value.trim() || `Manual M-Pesa Paybill payment for Unit ${effectiveUnit}`,
      phoneNumber: phoneNumber.value || currentTenant.value.phone,
      payerName: currentTenant.value.name,
      source: 'manual'
    })
    await fetchTenantProfile()
    successMessage.value = (saved as any).pendingVerification || saved.status === 'pending_verification'
      ? `Payment claim of ${formatKES(saved.amount)} submitted (Ref: ${saved.reference}). Management will verify and credit your balance shortly.`
      : `Payment of ${formatKES(saved.amount)} recorded (Ref: ${saved.reference}). Redirecting to your ledger...`
    setTimeout(() => {
      router.push('/tenant/payments')
    }, 1500)
  } catch (e: any) {
    error.value = e?.message || 'Could not record payment. Please check your connection and try again.'
  } finally {
    isSubmitting.value = false
  }
}

function switchPaymentMode(mode: 'kcb_stk' | 'direct_portal') {
  paymentMode.value = mode
  error.value = ''
  successMessage.value = ''
}
</script>

<template>
  <div class="page-body">
    <!-- Clean Minimalist Header -->
    <header class="page-intro" style="margin-bottom: 20px;">
      <div>
        <router-link to="/tenant/payments" class="text-button"
          style="margin-bottom: 10px; gap: 6px; font-weight: 500; font-size: 0.85rem; color: #475569; text-decoration: none; display: inline-flex; align-items: center;">
          <ArrowLeft :size="15" /> Back to payments
        </router-link>
        <p class="eyebrow"
          style="letter-spacing: 0.08em; color: #94a3b8; font-size: 0.74rem; font-weight: 600; text-transform: uppercase; margin: 0 0 4px;">
          RESIDENT PORTAL</p>
        <h1 style="font-size: 1.85rem; font-weight: 700; color: #0f172a; margin: 0 0 4px;">Pay Rent</h1>
        <p style="font-size: 0.88rem; color: #64748b; margin: 0;">Unit {{ currentUnit?.unitNumber ||
          activeLease?.unitNumber }} &middot; Quick & Secure M-Pesa Settlement</p>
      </div>
    </header>

    <div style="max-width: 540px;">
      <!-- Concise 1-Line Account Standing Banner -->
      <div v-if="standing.accountCredit > 0"
        style="padding: 12px 16px; background-color: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; margin-bottom: 18px; display: flex; align-items: center; justify-content: space-between; gap: 12px;">
        <div style="display: flex; align-items: center; gap: 8px; color: #166534; font-size: 0.84rem;">
          <CheckCircle2 :size="16" style="color: #16a34a; flex-shrink: 0;" />
          <span>
            <strong>Prepaid Credit: {{ formatKES(standing.accountCredit) }}</strong>
            &middot; Rent covered until {{ formatHumanDate(standing.nextDueDate) }}.
          </span>
        </div>
        <span
          style="background-color: #dcfce7; color: #15803d; font-size: 0.72rem; font-weight: 700; padding: 3px 8px; border-radius: 12px; white-space: nowrap;">
          Current
        </span>
      </div>

      <div v-else-if="standing.balance > 0"
        style="padding: 12px 16px; background-color: #fff7ed; border: 1px solid #fed7aa; border-radius: 8px; margin-bottom: 18px; display: flex; align-items: center; justify-content: space-between; gap: 12px;">
        <div style="display: flex; align-items: center; gap: 8px; color: #9a3412; font-size: 0.84rem;">
          <AlertCircle :size="16" style="color: #ea580c; flex-shrink: 0;" />
          <span>
            <strong>Payment Due: {{ formatKES(standing.balance) }}</strong>
            <span v-if="standing.isDepositDue">&middot; Includes Security Deposit</span>
          </span>
        </div>
        <span
          style="background-color: #ffedd5; color: #c2410c; font-size: 0.72rem; font-weight: 700; padding: 3px 8px; border-radius: 12px; white-space: nowrap;">
          Due Now
        </span>
      </div>

      <!-- Deposit Priority Notice (If deposit unpaid) -->
      <div v-if="isDepositUnpaid"
        style="padding: 10px 14px; background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; margin-bottom: 18px; font-size: 0.8rem; color: #1e40af; display: flex; align-items: center; gap: 8px;">
        <ShieldCheck :size="15" style="color: #2563eb; flex-shrink: 0;" />
        <span>Your initial payment automatically fulfills your rent deposit first.</span>
      </div>

      <!-- Payment Method Toggle 
      <div style="display: flex; gap: 8px; margin-bottom: 16px;">
        <button type="button"
          style="flex: 1; padding: 10px 14px; font-size: 0.86rem; font-weight: 600; border-radius: 8px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; transition: all 0.15s ease;"
          :style="paymentMode === 'kcb_stk'
            ? 'background-color: #0f172a; color: #ffffff; border: 1px solid #0f172a;'
            : 'background-color: #ffffff; color: #475569; border: 1px solid #cbd5e1;'"
          @click="switchPaymentMode('kcb_stk')">
          <Smartphone :size="16" />
          <span>M-Pesa STK Push</span>
        </button>

        <button type="button"
          style="flex: 1; padding: 10px 14px; font-size: 0.86rem; font-weight: 600; border-radius: 8px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; transition: all 0.15s ease;"
          :style="paymentMode === 'direct_portal'
            ? 'background-color: #0f172a; color: #ffffff; border: 1px solid #0f172a;'
            : 'background-color: #ffffff; color: #475569; border: 1px solid #cbd5e1;'"
          @click="switchPaymentMode('direct_portal')">
          <CreditCard :size="16" />
          <span>Paybill Manual</span>
        </button>
      </div>-->

      <!-- Mode 1: M-Pesa STK Push Form -->
      <form class="panel"
        style="padding: 22px; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.04);"
        @submit.prevent="handleKcbStkPush">
        <div v-if="error"
          style="padding: 10px 14px; background-color: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 6px; font-size: 0.82rem; margin-bottom: 16px;">
          {{ error }}
        </div>
        <div v-if="successMessage"
          style="padding: 10px 14px; background-color: #f0fdf4; border: 1px solid #bbf7d0; color: #166534; border-radius: 6px; font-size: 0.82rem; margin-bottom: 16px;">
          {{ successMessage }}
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">Payment
            Amount (KES)</label>
          <input v-model.number="amount" type="number" min="1" required placeholder="Amount in KES"
            style="width: 100%; padding: 10px 12px; font-size: 1.05rem; font-weight: 700; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; color: #0f172a;" />
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">M-Pesa
            Mobile Number</label>
          <PhoneInput v-model="phoneNumber" required placeholder="712345678" />
        </div>

        <div class="form-field" style="margin-bottom: 20px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">Description</label>
          <input v-model="notes" placeholder="Payment note"
            style="width: 100%; padding: 9px 12px; font-size: 0.88rem; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; color: #0f172a;" />
        </div>

        <!-- Waiting Card for User to Enter PIN -->
        <div v-if="isAwaitingPin"
          style="margin-bottom: 20px; padding: 14px 16px; background-color: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px;">
          <div style="display: flex; align-items: center; justify-content: space-between; gap: 10px;">
            <div
              style="display: flex; align-items: center; gap: 8px; color: #0f172a; font-weight: 600; font-size: 0.86rem;">
              <RefreshCw class="animate-spin" :size="16" style="color: #0284c7;" />
              <span>Awaiting M-Pesa PIN on your phone</span>
            </div>
            <button type="button"
              style="padding: 4px 10px; font-size: 0.76rem; font-weight: 600; background-color: #ffffff; border: 1px solid #cbd5e1; border-radius: 5px; cursor: pointer; color: #334155;"
              :disabled="isCheckingStatus" @click="handleCheckStatusNow">
              {{ isCheckingStatus ? 'Checking...' : 'Check Status' }}
            </button>
          </div>
          <p style="font-size: 0.8rem; color: #64748b; margin: 8px 0 0;">
            {{ stkStatusText }}
          </p>
        </div>

        <div
          style="display: flex; align-items: center; justify-content: flex-end; gap: 10px; padding-top: 14px; border-top: 1px solid #f1f5f9;">
          <router-link to="/tenant/payments"
            style="padding: 9px 16px; font-size: 0.84rem; font-weight: 600; color: #475569; text-decoration: none; border-radius: 6px; border: 1px solid #e2e8f0; background: #ffffff;">
            Cancel
          </router-link>
          <button type="submit" class="primary-button"
            style="padding: 10px 18px; font-size: 0.88rem; font-weight: 600; background-color: #0f172a; color: #ffffff; border: none; border-radius: 6px; cursor: pointer; display: flex; align-items: center; gap: 6px;"
            :disabled="isSubmitting || isAwaitingPin || isCheckingStatus">
            <Smartphone :size="15" />
            {{ isSubmitting ? 'Sending Prompt...' : isAwaitingPin ? 'Awaiting PIN...' : `Pay ${formatKES(Number(amount
              || 0))}` }}
          </button>
        </div>
      </form>

      <!-- Mode 2: Manual Paybill Form 
      <form v-else class="panel"
        style="padding: 22px; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.04);"
        @submit.prevent="handleDirectPay">
        <div v-if="error"
          style="padding: 10px 14px; background-color: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 6px; font-size: 0.82rem; margin-bottom: 16px;">
          {{ error }}
        </div>
        <div v-if="successMessage"
          style="padding: 10px 14px; background-color: #f0fdf4; border: 1px solid #bbf7d0; color: #166534; border-radius: 6px; font-size: 0.82rem; margin-bottom: 16px;">
          {{ successMessage }}
        </div>

        Clean Paybill Instructions Card
        <div
          style="padding: 14px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 18px; display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
          <div>
            <span
              style="font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; font-weight: 600;">Paybill
              Business No</span>
            <div class="mono" style="font-size: 1.12rem; font-weight: 700; color: #0f172a; margin-top: 3px;">
              {{ propertySettings.paybillNumber || '522522' }}</div>
          </div>
          <div>
            <span
              style="font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; font-weight: 600;">Account
              Number</span>
            <div class="mono" style="font-size: 1.12rem; font-weight: 700; color: #0f172a; margin-top: 3px;">
              LAPIS-{{ currentUnit?.unitNumber || activeLease?.unitNumber || currentTenant?.currentUnitNumber || 'UNIT' }}</div>
          </div>
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">Payment
            Amount (KES)</label>
          <input v-model.number="amount" type="number" min="1" required placeholder="Amount in KES"
            style="width: 100%; padding: 10px 12px; font-size: 1.05rem; font-weight: 700; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; color: #0f172a;" />
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">M-Pesa
            Transaction Code</label>
          <input v-model="reference" class="mono" required placeholder="e.g. QA12BC34DE (from your M-Pesa SMS)"
            style="width: 100%; padding: 10px 12px; font-size: 0.92rem; text-transform: uppercase; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; color: #0f172a;" />
        </div>

        <div class="form-field" style="margin-bottom: 20px;">
          <label
            style="display: block; font-size: 0.82rem; font-weight: 600; color: #334155; margin-bottom: 6px;">Description</label>
          <input v-model="notes" placeholder="Payment note"
            style="width: 100%; padding: 9px 12px; font-size: 0.88rem; border: 1px solid #cbd5e1; border-radius: 6px; box-sizing: border-box; color: #0f172a;" />
        </div>

        <div
          style="display: flex; align-items: center; justify-content: flex-end; gap: 10px; padding-top: 14px; border-top: 1px solid #f1f5f9;">
          <router-link to="/tenant/payments"
            style="padding: 9px 16px; font-size: 0.84rem; font-weight: 600; color: #475569; text-decoration: none; border-radius: 6px; border: 1px solid #e2e8f0; background: #ffffff;">
            Cancel
          </router-link>
          <button type="submit" class="primary-button"
            style="padding: 10px 18px; font-size: 0.88rem; font-weight: 600; background-color: #0f172a; color: #ffffff; border: none; border-radius: 6px; cursor: pointer; display: flex; align-items: center; gap: 6px;"
            :disabled="isSubmitting">
            <CreditCard :size="15" />
            {{ isSubmitting ? 'Confirming...' : 'Confirm Payment' }}
          </button>
        </div>
      </form>-->
    </div>
  </div>
</template>
