import { store, fetchFromBackend } from './data'

export interface RealtimeEventPayload {
  transaction?: any
  lease?: any
  callback?: any
  notification?: any
  auditRecord?: any
  record?: any
  checkoutRequestId?: string
  merchantRequestId?: string
  phoneNumber?: string
  status?: string
  resultDesc?: string
}

type EventCallback = (payload: RealtimeEventPayload) => void

const paymentListeners = new Set<EventCallback>()
const callbackListeners = new Set<EventCallback>()
const notificationListeners = new Set<EventCallback>()

let eventSource: EventSource | null = null
let reconnectTimer: any = null

export function reconnectSSE() {
  if (eventSource) {
    try {
      eventSource.close()
    } catch {}
    eventSource = null
  }
  initSSE()
}

export function initSSE() {
  if (typeof window === 'undefined') return
  if (eventSource) return

  try {
    const token = typeof window !== 'undefined' ? localStorage.getItem('lapis_jwt_token') : null
    if (!token) return // SSE requires authentication; reconnectSSE() starts stream after login
    const url = `/api/events?token=${encodeURIComponent(token)}`
    eventSource = new EventSource(url)

    eventSource.onopen = () => {
      // console.log('[SSE] Connected to real-time events stream')
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
    }

    eventSource.addEventListener('payment_received', async (event: MessageEvent) => {
      try {
        const data: RealtimeEventPayload = JSON.parse(event.data)
        // console.log('[SSE] Real-time payment_received:', data)

        if (data.transaction) {
          const tx = data.transaction
          const idx = store.transactions.findIndex(t => t.id === tx.id || (t.reference && t.reference === tx.reference))
          if (idx >= 0) {
            store.transactions[idx] = { ...store.transactions[idx], ...tx }
          } else {
            store.transactions.unshift(tx)
          }
        }

        if (data.lease) {
          const l = data.lease
          const idx = store.leases.findIndex(existing => existing.id === l.id)
          if (idx >= 0) {
            store.leases[idx] = { ...store.leases[idx], ...l }
          } else {
            store.leases.push(l)
          }
        }

        if (data.auditRecord) {
          const rec = data.auditRecord
          const idx = store.kcbLogs.findIndex(
            k => (k.id && k.id === rec.id) ||
                 (k.checkoutRequestId && k.checkoutRequestId === rec.checkoutRequestId) ||
                 (k.merchantRequestId && k.merchantRequestId === rec.merchantRequestId)
          )
          if (idx >= 0) {
            store.kcbLogs[idx] = { ...store.kcbLogs[idx], ...rec }
          } else {
            store.kcbLogs.unshift(rec)
          }
        }

        // Notify subscribers
        for (const listener of paymentListeners) {
          try { listener(data) } catch (e) { console.error(e) }
        }
      } catch (err) {
        console.error('[SSE] Failed to process payment_received event:', err)
      }
    })

    eventSource.addEventListener('kcb_callback', (event: MessageEvent) => {
      try {
        const data: RealtimeEventPayload = JSON.parse(event.data)
        // console.log('[SSE] Real-time kcb_callback:', data)

        if (data.auditRecord) {
          const rec = data.auditRecord
          const idx = store.kcbLogs.findIndex(
            k => (k.id && k.id === rec.id) ||
                 (k.checkoutRequestId && k.checkoutRequestId === rec.checkoutRequestId) ||
                 (k.merchantRequestId && k.merchantRequestId === rec.merchantRequestId)
          )
          if (idx >= 0) {
            store.kcbLogs[idx] = { ...store.kcbLogs[idx], ...rec }
          } else {
            store.kcbLogs.unshift(rec)
          }
        }

        // Notify subscribers
        for (const listener of callbackListeners) {
          try { listener(data) } catch (e) { console.error(e) }
        }
      } catch (err) {
        console.error('[SSE] Failed to process kcb_callback event:', err)
      }
    })

    eventSource.addEventListener('audit_updated', (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data)
        if (data.record) {
          const rec = data.record
          const idx = store.kcbLogs.findIndex(
            k => (k.id && k.id === rec.id) ||
                 (k.checkoutRequestId && k.checkoutRequestId === rec.checkoutRequestId) ||
                 (k.merchantRequestId && k.merchantRequestId === rec.merchantRequestId)
          )
          if (idx >= 0) {
            store.kcbLogs[idx] = { ...store.kcbLogs[idx], ...rec }
          } else {
            store.kcbLogs.unshift(rec)
          }
        }
        for (const listener of callbackListeners) {
          try { listener(data) } catch (e) { console.error(e) }
        }
      } catch (err) {
        console.error('[SSE] Failed to process audit_updated event:', err)
      }
    })

    eventSource.addEventListener('notification', (event: MessageEvent) => {
      try {
        const notif = JSON.parse(event.data)
        if (notif && notif.id) {
          const exists = store.notifications.some(n => n.id === notif.id)
          if (!exists) {
            store.notifications.unshift(notif)
          }
        }
        for (const listener of notificationListeners) {
          try { listener({ notification: notif }) } catch (e) { console.error(e) }
        }
      } catch (err) {
        console.error('[SSE] Failed to process notification event:', err)
      }
    })

    eventSource.onerror = () => {
      // EventSource automatically tries to reconnect, but if it closes, retry after delay
      if (eventSource && eventSource.readyState === EventSource.CLOSED) {
        eventSource.close()
        eventSource = null
        if (!reconnectTimer) {
          reconnectTimer = setTimeout(() => {
            reconnectTimer = null
            initSSE()
          }, 5000)
        }
      }
    }
  } catch (err) {
    console.warn('[SSE] EventSource initialization failed:', err)
  }
}

export function onPaymentReceived(cb: EventCallback): () => void {
  paymentListeners.add(cb)
  return () => paymentListeners.delete(cb)
}

export function onKcbCallback(cb: EventCallback): () => void {
  callbackListeners.add(cb)
  return () => callbackListeners.delete(cb)
}

export function onNotification(cb: EventCallback): () => void {
  notificationListeners.add(cb)
  return () => notificationListeners.delete(cb)
}
