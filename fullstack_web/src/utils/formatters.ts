// Strict Human-Readable Date & Currency Formatting Utilities for Lapis Suites

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function getOrdinalSuffix(day: number): string {
  if (day > 3 && day < 21) return 'th'
  switch (day % 10) {
    case 1: return 'st'
    case 2: return 'nd'
    case 3: return 'rd'
    default: return 'th'
  }
}

/**
 * Converts a raw date string (e.g. "2026-11-12" or "2026-11-12 09:22:15")
 * into a warm, human-readable format: "12th Nov 2026"
 */
export function formatHumanDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—'
  const cleanDate = dateStr.includes(' ') ? dateStr.split(' ')[0] : dateStr.includes('T') ? dateStr.split('T')[0] : dateStr
  const parts = cleanDate.split('-')
  if (parts.length !== 3) return dateStr

  const year = parts[0]
  const monthIdx = parseInt(parts[1], 10) - 1
  const day = parseInt(parts[2], 10)

  if (isNaN(day) || isNaN(monthIdx) || monthIdx < 0 || monthIdx > 11) {
    return dateStr
  }

  const monthName = MONTHS[monthIdx]
  return `${day}${getOrdinalSuffix(day)} ${monthName} ${year}`
}

/**
 * Converts a raw date-time string (e.g. "2026-11-04 09:22:15" or ISO)
 * into a warm human-readable format: "4th Nov 2026 · 09:22"
 */
export function formatHumanDateTime(dateTimeStr: string | null | undefined): string {
  if (!dateTimeStr) return '—'
  
  let datePart = dateTimeStr
  let timePart = ''

  if (dateTimeStr.includes(' ')) {
    const parts = dateTimeStr.split(' ')
    datePart = parts[0]
    timePart = parts[1].slice(0, 5) // HH:mm
  } else if (dateTimeStr.includes('T')) {
    const parts = dateTimeStr.split('T')
    datePart = parts[0]
    timePart = parts[1].slice(0, 5) // HH:mm
  }

  const formattedDate = formatHumanDate(datePart)
  if (!timePart) return formattedDate

  return `${formattedDate} · ${timePart}`
}

/**
 * Standard Kenyan Shillings currency formatter: KES 42,000
 */
export function formatKES(val: number | string | null | undefined): string {
  const num = typeof val === 'number' ? val : Number(val) || 0
  return `KES ${num.toLocaleString('en-KE')}`
}

/**
 * Calculates days remaining from today (2026-11-12) until target date
 */
export function getDaysRemaining(targetDateStr: string): number {
  if (!targetDateStr) return 0
  const clean = targetDateStr.split('T')[0].split(' ')[0]
  const target = new Date(clean)
  const today = new Date('2026-11-12') // Fixed project anchor date
  const diffTime = target.getTime() - today.getTime()
  return Math.ceil(diffTime / (1000 * 60 * 60 * 24))
}
