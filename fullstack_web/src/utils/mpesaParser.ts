/**
 * Utility for parsing Kenyan Safaricom M-Pesa SMS messages
 * Extracts Reference code, Amount, Date, Time, Sender Phone/Name, and Account/Unit
 */

export interface ParsedMpesaMessage {
  success: boolean
  rawText: string
  reference?: string
  amount?: number
  date?: string // YYYY-MM-DD
  time?: string
  phoneNumber?: string
  payerName?: string
  accountNumber?: string
  error?: string
}

export function parseMpesaMessage(rawText: string): ParsedMpesaMessage {
  if (!rawText || typeof rawText !== 'string' || !rawText.trim()) {
    return { success: false, rawText: '', error: 'Please paste a valid M-Pesa SMS message.' }
  }

  const text = rawText.trim()
  const result: ParsedMpesaMessage = {
    success: false,
    rawText: text
  }

  // 1. Extract Transaction Code (Reference)
  // Usually at the beginning: e.g. "QA12BC34DE Confirmed." or "Confirmed. QA12BC34DE"
  const refMatch = text.match(/\b([A-Z0-9]{8,12})\s+Confirmed/i) ||
                   text.match(/Confirmed\.\s+([A-Z0-9]{8,12})/i) ||
                   text.match(/\b([A-Z0-9]{10})\b/)

  if (refMatch && refMatch[1]) {
    result.reference = refMatch[1].toUpperCase()
  }

  // 2. Extract Amount (e.g. Ksh15,000.00, Ksh. 2,500, KES 50,000)
  const amountMatch = text.match(/(?:Ksh\.?|KES)\s*([0-9,]+(?:\.[0-9]{1,2})?)/i) ||
                      text.match(/received\s+Ksh\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)/i) ||
                      text.match(/sent\s+to.*?Ksh\.?\s*([0-9,]+(?:\.[0-9]{1,2})?)/i)

  if (amountMatch && amountMatch[1]) {
    const cleanNum = amountMatch[1].replace(/,/g, '')
    const parsedAmt = parseFloat(cleanNum)
    if (!isNaN(parsedAmt) && parsedAmt > 0) {
      result.amount = parsedAmt
    }
  }

  // 3. Extract Date and Time
  // Format examples: "on 13/11/26 at 8:15 AM", "on 13/11/2026 at 10:30 PM", "on 2026-11-13"
  const dateMatch = text.match(/on\s+([0-9]{1,2}[\/\-\.][0-9]{1,2}[\/\-\.][0-9]{2,4})/i)
  if (dateMatch && dateMatch[1]) {
    const rawDate = dateMatch[1]
    const parts = rawDate.split(/[\/\-\.]/)
    if (parts.length === 3) {
      let day = parseInt(parts[0], 10)
      let month = parseInt(parts[1], 10)
      let year = parseInt(parts[2], 10)

      // Check if it's YYYY-MM-DD
      if (parts[0].length === 4) {
        year = parseInt(parts[0], 10)
        month = parseInt(parts[1], 10)
        day = parseInt(parts[2], 10)
      } else if (year < 100) {
        year += 2000
      }

      const yyyy = String(year)
      const mm = String(month).padStart(2, '0')
      const dd = String(day).padStart(2, '0')
      result.date = `${yyyy}-${mm}-${dd}`
    }
  }

  const timeMatch = text.match(/at\s+([0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\s*(?:AM|PM|am|pm)?)/i)
  if (timeMatch && timeMatch[1]) {
    result.time = timeMatch[1].trim()
  }

  // 4. Extract Sender / Payer Name and Phone Number
  // Examples:
  // "from JOHN DOE 0712345678"
  // "received from 254712345678 JOHN DOE"
  // "from 0797204141 Stallone Odhiambo"
  const phoneMatch = text.match(/\b(254[17]\d{8}|0[17]\d{8}|\+254[17]\d{8})\b/)
  if (phoneMatch && phoneMatch[1]) {
    let p = phoneMatch[1].replace(/\D/g, '')
    if (p.startsWith('254')) p = '0' + p.slice(3)
    result.phoneNumber = p
  }

  const nameMatch = text.match(/from\s+([A-Za-z\s]{2,35}?)(?:\s+(?:0[17]\d{8}|254[17]\d{8}|on|\.))/i) ||
                    text.match(/received from\s+(?:[0-9\+]+\s+)?([A-Za-z\s]{2,35}?)(?:\.|\s+on|\s+Account)/i)

  if (nameMatch && nameMatch[1]) {
    const candidateName = nameMatch[1].trim().replace(/\b(Ksh|KES|new|utility|balance)\b/gi, '').trim()
    if (candidateName.length >= 2 && !/^\d+$/.test(candidateName)) {
      result.payerName = candidateName
    }
  }

  // 5. Extract Account / Unit reference
  // Examples: "for account 125F", "Account: 125F", "Ref. 125F", "Acc. 125F"
  const accountMatch = text.match(/(?:account|acc\.?|ref\.?)\s*[:\-]?\s*([A-Za-z0-9\-]{2,10})/i) ||
                       text.match(/for\s+account\s+([A-Za-z0-9\-]{2,10})/i)

  if (accountMatch && accountMatch[1]) {
    const acc = accountMatch[1].trim().toUpperCase()
    // Ignore common stopwords like "ON", "NEW", "BALANCE", "IS"
    if (!['ON', 'NEW', 'BALANCE', 'IS', 'AT', 'THE', 'CONFIRMED'].includes(acc)) {
      result.accountNumber = acc
    }
  }

  // If at least reference or amount was extracted, consider successful
  if (result.reference || result.amount) {
    result.success = true
    if (!result.date) {
      result.date = new Date().toISOString().slice(0, 10)
    }
  } else {
    result.error = 'Could not extract M-Pesa transaction details. Please check the pasted message format.'
  }

  return result
}
