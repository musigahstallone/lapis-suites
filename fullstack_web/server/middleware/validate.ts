const ISO_DATE_RE = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function isIsoDate(val: unknown): val is string {
  if (typeof val !== 'string') return false
  const s = val.trim()
  if (!ISO_DATE_RE.test(s)) return false
  const d = new Date(`${s}T00:00:00Z`)
  return !isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s
}

export function isValidEmail(val: unknown): boolean {
  if (typeof val !== 'string') return false
  const s = val.trim().toLowerCase()
  return s.length <= 160 && EMAIL_RE.test(s)
}

export function parsePositiveAmount(val: unknown, max = 10_000_000): number | null {
  const num = Number(val)
  if (!Number.isFinite(num) || num <= 0 || num > max) return null
  return Math.round(num * 100) / 100
}

export function parseNonNegativeAmount(val: unknown, max = 10_000_000): number | null {
  const num = Number(val)
  if (!Number.isFinite(num) || num < 0 || num > max) return null
  return Math.round(num * 100) / 100
}

export function cleanString(val: unknown, maxLength = 300): string {
  if (val === undefined || val === null) return ''
  return String(val).trim().slice(0, maxLength)
}

export function isValidEnum<T extends string>(val: unknown, allowed: readonly T[]): val is T {
  return typeof val === 'string' && (allowed as readonly string[]).includes(val)
}
