<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { LogIn, AlertCircle, UserPlus, Eye, EyeOff, ShieldCheck } from 'lucide-vue-next'
import { loginWithCredentials } from '../../data'

const router = useRouter()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const error = ref('')
const isLoading = ref(false)

async function handleSignIn() {
  error.value = ''
  if (!email.value.trim() || !password.value) {
    error.value = 'Please enter both your email address and password.'
    return
  }

  isLoading.value = true
  try {
    const res = await loginWithCredentials(email.value, password.value)
    if (!res.ok) {
      error.value = res.error || 'Invalid email or password.'
      return
    }

    if (res.requiresAccountSetup) {
      sessionStorage.setItem(
        'lapis_recovery_challenge',
        JSON.stringify({
          email: res.email || email.value.trim().toLowerCase(),
          maskedPhone: '',
          expiresAt: Date.now() + (res.expiresInSeconds || 600) * 1000
        })
      )
      router.push({
        path: '/verify-code',
        query: { mode: 'recovery', email: res.email || email.value.trim().toLowerCase() }
      })
      return
    }

    if (res.requiresOtp && res.challengeToken) {
      sessionStorage.setItem(
        'lapis_admin_otp_challenge',
        JSON.stringify({
          challengeToken: res.challengeToken,
          email: res.email || email.value.trim().toLowerCase(),
          maskedPhone: res.maskedPhone || '',
          expiresAt: Date.now() + (res.expiresInSeconds || 600) * 1000
        })
      )
      router.push({
        path: '/verify-code',
        query: { mode: 'admin-login', email: res.email || email.value.trim().toLowerCase() }
      })
      return
    }

    if (res.role === 'landlord') {
      if (res.needsAdminPhoneSetup) {
        router.push('/settings')
      } else {
        router.push('/dashboard')
      }
    } else {
      router.push('/tenant/home')
    }
  } catch (err: any) {
    error.value = err.message || 'Unable to connect to authentication server.'
  } finally {
    isLoading.value = false
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
        <p class="eyebrow">PORTAL ACCESS</p>
        <h1>Executive property operations &amp; resident living.</h1>
        <p>Unified, secure authentication for property administrators and residents with SMS two-factor protection on every admin sign-in.</p>
      </div>

      <p class="quote">
        “Lapis Suites keeps our portfolio structured, collections reconciled, and residents updated.”
        <small>— Lapis Suites Management Desk</small>
      </p>
    </aside>

    <section class="auth-main">
      <form class="login-card" @submit.prevent="handleSignIn">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <p class="eyebrow">ACCOUNT SIGN IN</p>
        <h1>Sign in to your portal</h1>
        <p class="subtle">Enter your registered email and password to access your dashboard.</p>

        <div v-if="error" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ error }}</span>
        </div>

        <label>
          Email address
          <input
            v-model="email"
            type="email"
            required
            autocomplete="email"
            placeholder="you@lapissuites.com"
          />
        </label>

        <label>
          Password
          <router-link to="/forgot-password">Forgot password?</router-link>
          <div class="password-field">
            <input
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              required
              autocomplete="current-password"
              placeholder="Enter your password"
            />
            <button
              type="button"
              class="password-toggle"
              :aria-label="showPassword ? 'Hide password' : 'Show password'"
              @click="showPassword = !showPassword"
            >
              <EyeOff v-if="showPassword" :size="16" />
              <Eye v-else :size="16" />
            </button>
          </div>
        </label>

        <div class="auth-security-note">
          <ShieldCheck :size="15" />
          <span>Administrator sign-ins send a 6-digit SMS verification code to the registered admin number.</span>
        </div>

        <button type="submit" class="primary-button submit" :disabled="isLoading">
          <LogIn :size="16" />
          <span>{{ isLoading ? 'Verifying credentials...' : 'Sign In to Portal' }}</span>
        </button>

        <div class="auth-divider-footer">
          <p>Need a resident account?</p>
          <router-link to="/register" class="text-button auth-inline-link">
            <UserPlus :size="15" />
            <span>Register as Resident</span>
          </router-link>
        </div>
      </form>
    </section>
  </main>
</template>
