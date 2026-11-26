/**
 * Gracefully parses JSON responses from fetch() so network drops, proxy 502 HTML pages,
 * or non-JSON gateway responses never show raw "Unexpected token '<'" syntax errors to users.
 */
export async function safeParseJson(res: Response): Promise<{ ok: boolean; status: number; data: any; error?: string }> {
  let rawText = ''
  try {
    rawText = await res.text()
  } catch {
    return {
      ok: false,
      status: res.status || 0,
      data: null,
      error: 'Connection interrupted while reading server response. Please check your internet and try again.'
    }
  }

  if (!rawText) {
    return {
      ok: res.ok,
      status: res.status,
      data: {},
      error: res.ok ? undefined : 'The server returned an empty response. Please try again.'
    }
  }

  try {
    const parsed = JSON.parse(rawText)
    if (!res.ok) {
      return {
        ok: false,
        status: res.status,
        data: parsed,
        error: parsed?.error || parsed?.message || 'Request could not be completed. Please try again.'
      }
    }
    return { ok: true, status: res.status, data: parsed }
  } catch {
    // Response was HTML (e.g. Cloudflare / Nginx 502/504 page) or plain text
    const isServerUnavailable = res.status >= 500 || rawText.trim().startsWith('<')
    return {
      ok: false,
      status: res.status,
      data: null,
      error: isServerUnavailable
        ? 'Service is temporarily unreachable. Please check your internet connection and try again in a moment.'
        : 'Unexpected response from the server. Please try again.'
    }
  }
}

export async function safeFetchJson(url: string, init?: RequestInit): Promise<{ ok: boolean; status: number; data: any; error?: string }> {
  try {
    const res = await fetch(url, init)
    return await safeParseJson(res)
  } catch {
    return {
      ok: false,
      status: 0,
      data: null,
      error: 'Unable to reach the server. Please check your internet connection and try again.'
    }
  }
}
