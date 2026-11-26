<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, AlertCircle, Send, Smartphone } from 'lucide-vue-next'

const router = useRouter()
const email = ref('')
const isSending = ref(false)
const error = ref('')

async function handleSubmit() {
  error.value = ''
  const cleanEmail = email.value.trim().toLowerCase()
  if (!cleanEmail) {
    error.value = 'Please enter your registered email address.'
    return
  }

  isSending.value = true
  try {
    const res = await fetch('/api/auth/forgot-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: cleanEmail })
    })
    const data = await res.json()
    if (!res.ok) {
      error.value = data.error || 'Failed to send SMS verification code. Please try again.'
      return
    }

    sessionStorage.setItem(
      'lapis_recovery_challenge',
      JSON.stringify({
        email: data.email || cleanEmail,
        maskedPhone: data.maskedPhone || '',
        expiresAt: Date.now() + (data.expiresInSeconds || 600) * 1000
      })
    )

    router.push({
      path: '/verify-code',
      query: { mode: 'recovery', email: data.email || cleanEmail }
    })
  } catch (err: any) {
    error.value = err.message || 'Network error connecting to recovery service.'
  } finally {
    isSending.value = false
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
        <p class="eyebrow">PASSWORD RECOVERY</p>
        <h1>Recover access via SMS OTP.</h1>
        <p>Enter your account email address and we will text a 6-digit one-time verification code to the mobile number registered on your profile.</p>
      </div>

      <p class="quote">
        “Verification codes expire automatically after 10 minutes and can only be used once.”
        <small>— Lapis Suites Account Security</small>
      </p>
    </aside>

    <section class="auth-main">
      <form class="login-card" @submit.prevent="handleSubmit">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <div class="auth-steps" aria-label="Recovery steps">
          <div class="auth-step active"><span>1</span> Account</div>
          <div class="auth-step-line"></div>
          <div class="auth-step"><span>2</span> SMS OTP</div>
          <div class="auth-step-line"></div>
          <div class="auth-step"><span>3</span> New Password</div>
        </div>

        <p class="eyebrow">STEP 1 OF 3</p>
        <h1>Forgot password</h1>
        <p class="subtle">Enter your registered email address to receive a 6-digit SMS OTP.</p>

        <div v-if="error" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ error }}</span>
        </div>

        <label>
          Registered Email Address
          <input
            v-model="email"
            type="email"
            required
            autocomplete="email"
            placeholder="you@lapissuites.com"
          />
        </label>

        <div class="auth-security-note">
          <Smartphone :size="15" />
          <span>The 6-digit OTP will be sent to the Kenyan mobile phone linked to this account.</span>
        </div>

        <button type="submit" class="primary-button submit" :disabled="isSending">
          <Send :size="15" />
          <span>{{ isSending ? 'Sending SMS OTP...' : 'Send SMS Verification Code' }}</span>
        </button>

        <div class="auth-footer-nav center">
          <router-link to="/login" class="text-button auth-inline-link">
            <ArrowLeft :size="15" />
            <span>Back to sign in</span>
          </router-link>
        </div>
      </form>
    </section>
  </main>
</template>
