<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import {
  ArrowLeft,
  AlertCircle,
  CheckCircle2,
  RotateCw,
  ShieldCheck,
  Smartphone,
  Clock
} from 'lucide-vue-next'
import { verifyAdminLoginOtp, resendAdminLoginOtp } from '../../data'

const router = useRouter()
const route = useRoute()

const mode = computed<'admin-login' | 'recovery'>(() => {
  return route.query.mode === 'admin-login' ? 'admin-login' : 'recovery'
})

const email = ref('')
const maskedPhone = ref('')
const challengeToken = ref('')
const digits = ref<string[]>(['', '', '', '', '', ''])
const inputRefs = ref<(HTMLInputElement | null)[]>([])

const error = ref('')
const info = ref('')
const isVerifying = ref(false)
const isResending = ref(false)
const resendCooldown = ref(30)
const expiresInSeconds = ref(600)

let timerHandle: ReturnType<typeof setInterval> | null = null

const otpCode = computed(() => digits.value.join(''))
const isCodeComplete = computed(() => otpCode.value.length === 6 && /^\d{6}$/.test(otpCode.value))

const formattedExpiry = computed(() => {
  const secs = Math.max(0, expiresInSeconds.value)
  const mins = Math.floor(secs / 60)
  const rem = secs % 60
  return `${mins}:${String(rem).padStart(2, '0')}`
})

function loadChallengeState() {
  if (mode.value === 'admin-login') {
    try {
      const raw = sessionStorage.getItem('lapis_admin_otp_challenge')
      if (raw) {
        const parsed = JSON.parse(raw)
        challengeToken.value = parsed.challengeToken || ''
        email.value = parsed.email || (route.query.email as string) || ''
        maskedPhone.value = parsed.maskedPhone || ''
        if (parsed.expiresAt) {
          expiresInSeconds.value = Math.max(0, Math.floor((parsed.expiresAt - Date.now()) / 1000))
        }
      }
    } catch {}
    if (!email.value && route.query.email) {
      email.value = String(route.query.email)
    }
  } else {
    try {
      const raw = sessionStorage.getItem('lapis_recovery_challenge')
      if (raw) {
        const parsed = JSON.parse(raw)
        email.value = parsed.email || (route.query.email as string) || ''
        maskedPhone.value = parsed.maskedPhone || ''
        if (parsed.expiresAt) {
          expiresInSeconds.value = Math.max(0, Math.floor((parsed.expiresAt - Date.now()) / 1000))
        }
      }
    } catch {}
    if (!email.value && route.query.email) {
      email.value = String(route.query.email)
    }
  }
}

onMounted(() => {
  loadChallengeState()
  nextTick(() => {
    inputRefs.value[0]?.focus()
  })

  timerHandle = setInterval(() => {
    if (resendCooldown.value > 0) resendCooldown.value--
    if (expiresInSeconds.value > 0) expiresInSeconds.value--
  }, 1000)
})

onUnmounted(() => {
  if (timerHandle) clearInterval(timerHandle)
})

function handleDigitInput(index: number, event: Event) {
  const input = event.target as HTMLInputElement
  const raw = input.value.replace(/\D/g, '')

  if (raw.length > 1) {
    // Handle autofill or multi-char paste into a single box
    const chars = raw.slice(0, 6).split('')
    digits.value = ['', '', '', '', '', '']
    chars.forEach((ch, idx) => {
      digits.value[idx] = ch
    })
    const focusIdx = Math.min(chars.length, 5)
    nextTick(() => inputRefs.value[focusIdx]?.focus())
    return
  }

  digits.value[index] = raw
  if (raw && index < 5) {
    nextTick(() => inputRefs.value[index + 1]?.focus())
  }
}

function handleDigitKeydown(index: number, event: KeyboardEvent) {
  if (event.key === 'Backspace') {
    if (digits.value[index]) {
      digits.value[index] = ''
    } else if (index > 0) {
      digits.value[index - 1] = ''
      nextTick(() => inputRefs.value[index - 1]?.focus())
    }
  } else if (event.key === 'ArrowLeft' && index > 0) {
    inputRefs.value[index - 1]?.focus()
  } else if (event.key === 'ArrowRight' && index < 5) {
    inputRefs.value[index + 1]?.focus()
  }
}

function handlePaste(event: ClipboardEvent) {
  const pasted = (event.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, 6)
  if (!pasted) return
  event.preventDefault()
  digits.value = ['', '', '', '', '', '']
  pasted.split('').forEach((ch, idx) => {
    digits.value[idx] = ch
  })
  const focusIdx = Math.min(pasted.length, 5)
  nextTick(() => inputRefs.value[focusIdx]?.focus())
}

async function handleVerify() {
  error.value = ''
  info.value = ''

  if (!isCodeComplete.value) {
    error.value = 'Please enter all 6 digits of the SMS verification code.'
    return
  }

  if (mode.value === 'admin-login') {
    if (!challengeToken.value) {
      error.value = 'Your admin login session has expired. Please return to Sign In.'
      return
    }

    isVerifying.value = true
    try {
      const res = await verifyAdminLoginOtp(challengeToken.value, otpCode.value)
      if (!res.ok) {
        error.value = res.error || 'Verification code is invalid or expired.'
        digits.value = ['', '', '', '', '', '']
        nextTick(() => inputRefs.value[0]?.focus())
        return
      }
      sessionStorage.removeItem('lapis_admin_otp_challenge')
      router.push('/dashboard')
    } catch (err: any) {
      error.value = err.message || 'Unable to verify OTP with server.'
    } finally {
      isVerifying.value = false
    }
    return
  }

  // Password recovery OTP verification
  if (!email.value) {
    error.value = 'Email address is missing. Please restart password recovery.'
    return
  }

  isVerifying.value = true
  try {
    const res = await fetch('/api/auth/verify-code', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.value.trim().toLowerCase(), code: otpCode.value })
    })
    const data = await res.json()
    if (!res.ok) {
      error.value = data.error || 'Verification code is invalid or has expired.'
      digits.value = ['', '', '', '', '', '']
      nextTick(() => inputRefs.value[0]?.focus())
      return
    }

    sessionStorage.setItem(
      'lapis_reset_session',
      JSON.stringify({
        email: data.email || email.value.trim().toLowerCase(),
        resetToken: data.resetToken || '',
        code: otpCode.value
      })
    )
    sessionStorage.removeItem('lapis_recovery_challenge')

    router.push({
      path: '/reset-password',
      query: { email: data.email || email.value.trim().toLowerCase() }
    })
  } catch (err: any) {
    error.value = err.message || 'Unable to connect to verification service.'
  } finally {
    isVerifying.value = false
  }
}

async function handleResend() {
  if (resendCooldown.value > 0 || isResending.value) return
  error.value = ''
  info.value = ''
  isResending.value = true

  try {
    if (mode.value === 'admin-login') {
      if (!challengeToken.value) {
        error.value = 'Login session expired. Please sign in again.'
        return
      }
      const res = await resendAdminLoginOtp(challengeToken.value)
      if (!res.ok) {
        error.value = res.error || 'Failed to resend admin OTP.'
        return
      }
      if (res.challengeToken) challengeToken.value = res.challengeToken
      if (res.maskedPhone) maskedPhone.value = res.maskedPhone
      expiresInSeconds.value = res.expiresInSeconds || 600
      sessionStorage.setItem(
        'lapis_admin_otp_challenge',
        JSON.stringify({
          challengeToken: challengeToken.value,
          email: email.value,
          maskedPhone: maskedPhone.value,
          expiresAt: Date.now() + expiresInSeconds.value * 1000
        })
      )
      resendCooldown.value = 30
      digits.value = ['', '', '', '', '', '']
      info.value = res.message || 'A fresh 6-digit SMS OTP has been sent.'
      nextTick(() => inputRefs.value[0]?.focus())
    } else {
      if (!email.value) {
        error.value = 'Email address is missing. Please restart password recovery.'
        return
      }
      const res = await fetch('/api/auth/forgot-password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.value.trim().toLowerCase() })
      })
      const data = await res.json()
      if (!res.ok) {
        error.value = data.error || 'Failed to resend SMS OTP.'
        return
      }
      if (data.maskedPhone) maskedPhone.value = data.maskedPhone
      expiresInSeconds.value = data.expiresInSeconds || 600
      sessionStorage.setItem(
        'lapis_recovery_challenge',
        JSON.stringify({
          email: email.value,
          maskedPhone: maskedPhone.value,
          expiresAt: Date.now() + expiresInSeconds.value * 1000
        })
      )
      resendCooldown.value = 30
      digits.value = ['', '', '', '', '', '']
      info.value = data.message || 'A fresh 6-digit SMS OTP has been sent.'
      nextTick(() => inputRefs.value[0]?.focus())
    }
  } catch {
    error.value = 'Network error while resending SMS OTP.'
  } finally {
    isResending.value = false
  }
}
</script>

<template>
  <main class="auth-page">
    <aside class="auth-aside">
      <div class="brand">
        <span class="brand-mark">L</span>
        LAPIS SUITES
      </div>

      <div class="auth-copy">
        <p class="eyebrow">{{ mode === 'admin-login' ? 'ADMIN TWO-FACTOR SECURITY' : 'SMS VERIFICATION' }}</p>
        <h1>{{ mode === 'admin-login' ? 'Verify administrator sign-in.' : 'Confirm your identity.' }}</h1>
        <p>
          {{
            mode === 'admin-login'
              ? 'Enter the 6-digit one-time passcode texted to your registered administrator mobile number to unlock the management console.'
              : 'Enter the 6-digit one-time code sent via SMS to confirm your identity before resetting your password.'
          }}
        </p>
      </div>

      <p class="quote">
        “Every privileged session and credential change is protected by live SMS OTP verification.”
        <small>— Lapis Suites Security</small>
      </p>
    </aside>

    <section class="auth-main">
      <form class="login-card" @submit.prevent="handleVerify">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <div v-if="mode === 'admin-login'" class="auth-steps" aria-label="Admin sign-in steps">
          <div class="auth-step done"><span>✓</span> Credentials</div>
          <div class="auth-step-line done"></div>
          <div class="auth-step active"><span>2</span> SMS OTP</div>
        </div>
        <div v-else class="auth-steps" aria-label="Recovery steps">
          <div class="auth-step done"><span>✓</span> Account</div>
          <div class="auth-step-line done"></div>
          <div class="auth-step active"><span>2</span> SMS OTP</div>
          <div class="auth-step-line"></div>
          <div class="auth-step"><span>3</span> New Password</div>
        </div>

        <p class="eyebrow">{{ mode === 'admin-login' ? 'STEP 2 OF 2 · ADMIN 2FA' : 'STEP 2 OF 3 · VERIFICATION' }}</p>
        <h1>Enter SMS OTP</h1>
        <p class="subtle">
          We sent a 6-digit code via SMS to
          <strong class="mono">{{ maskedPhone || 'your registered phone' }}</strong>
          <template v-if="email"> for <strong>{{ email }}</strong></template>.
        </p>

        <div v-if="error" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ error }}</span>
        </div>

        <div v-if="info" class="auth-alert success">
          <CheckCircle2 :size="16" class="auth-alert-icon" />
          <span>{{ info }}</span>
        </div>

        <div class="otp-header-row">
          <span class="otp-label">
            <Smartphone :size="14" />
            6-Digit Verification Code
          </span>
          <span :class="['otp-timer', { expired: expiresInSeconds === 0 }]">
            <Clock :size="13" />
            {{ expiresInSeconds > 0 ? `Expires in ${formattedExpiry}` : 'Code expired' }}
          </span>
        </div>

        <div class="otp-grid" @paste="handlePaste">
          <input
            v-for="(_, idx) in digits"
            :key="idx"
            :ref="(el) => { inputRefs[idx] = el as HTMLInputElement | null }"
            v-model="digits[idx]"
            type="text"
            inputmode="numeric"
            autocomplete="one-time-code"
            maxlength="6"
            class="otp-digit"
            :aria-label="`OTP digit ${idx + 1}`"
            @input="handleDigitInput(idx, $event)"
            @keydown="handleDigitKeydown(idx, $event)"
          />
        </div>

        <button
          type="submit"
          class="primary-button submit"
          :disabled="isVerifying || !isCodeComplete"
        >
          <ShieldCheck :size="16" />
          <span>
            {{
              isVerifying
                ? 'Verifying code...'
                : mode === 'admin-login'
                  ? 'Verify & Sign In'
                  : 'Verify & Continue'
            }}
          </span>
        </button>

        <div class="auth-footer-nav between">
          <router-link
            :to="mode === 'admin-login' ? '/login' : '/forgot-password'"
            class="text-button auth-inline-link"
          >
            <ArrowLeft :size="15" />
            <span>{{ mode === 'admin-login' ? 'Back to sign in' : 'Change email' }}</span>
          </router-link>

          <button
            type="button"
            class="text-button auth-inline-link"
            :disabled="isResending || resendCooldown > 0"
            @click="handleResend"
          >
            <RotateCw :size="14" :class="{ 'animate-spin': isResending }" />
            <span v-if="isResending">Sending...</span>
            <span v-else-if="resendCooldown > 0">Resend in {{ resendCooldown }}s</span>
            <span v-else>Resend SMS OTP</span>
          </button>
        </div>
      </form>
    </section>
  </main>
</template>
