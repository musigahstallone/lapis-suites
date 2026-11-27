import { jsPDF } from 'jspdf'
import type { Lease, Tenant, Unit } from '../types'
import { propertySettings } from '../data'
import { formatKES, formatHumanDate } from './formatters'

const NAVY = [17, 27, 53] as const // #111B35
const EMERALD = [5, 150, 105] as const // #059669
const AMBER = [180, 83, 9] as const // #B45309
const AMBER_BG = [255, 251, 235] as const // #FFFBEB
const AMBER_BORDER = [253, 230, 138] as const // #FDE68A
const TEXT_DARK = [23, 32, 51] as const // #172033
const TEXT_MUTED = [100, 116, 139] as const // #64748B
const BG_LIGHT = [248, 250, 252] as const // #F8FAFC
const BORDER = [226, 232, 240] as const // #E2E8F0

function formatUnitType(raw?: string): string {
  const clean = (raw || 'Apartment Suite').replace(/[-_]/g, ' ').trim()
  return clean.replace(/\b\w/g, c => c.toUpperCase())
}

function addPageFooter(doc: jsPDF, refLabel: string, propertyName: string) {
  const totalPages = doc.getNumberOfPages()
  for (let i = 1; i <= totalPages; i++) {
    doc.setPage(i)
    doc.setDrawColor(...BORDER)
    doc.line(18, 282, 192, 282)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(7.8)
    doc.setTextColor(...TEXT_MUTED)
    doc.text(`${propertyName} · ${refLabel} · Governed by the Laws of Kenya`, 18, 287)
    doc.text(`Page ${i} of ${totalPages}`, 192, 287, { align: 'right' })
  }
}

export function generateLeaseAgreementPdf(
  lease: Lease,
  tenant?: Tenant | null,
  unit?: Unit | null
): jsPDF {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4'
  })

  const propertyName = propertySettings.propertyName || 'Lapis Suites'
  const landlordCompany = propertySettings.paybillRecipientName || 'LAPIS APARTMENTS LIMITED'
  const paybill = propertySettings.paybillNumber || '522533'
  const accountNo = propertySettings.accountNumber || '8107578'
  const rentDueDay = propertySettings.rentDueDay || 5
  const landlordEmail = propertySettings.contactEmail || 'lapissuites@gmail.com'
  const landlordPhone = propertySettings.contactPhone || '+254 797 204 141'
  const address = propertySettings.address || 'Nairobi, Kenya'

  const residentName = tenant?.name || lease.tenantName || 'Resident'
  const residentId = tenant?.nationalId || 'On file'
  const residentPhone = tenant?.phone || 'On file'
  const residentEmail = tenant?.email || 'On file'
  const unitNo = lease.unitNumber || unit?.unitNumber || 'N/A'
  const unitTypeLabel = formatUnitType(lease.unitType || unit?.type)
  const depositStatus = lease.depositPaid ? 'Verified Paid' : 'Pending Settlement'
  const issueDate = formatHumanDate(new Date().toISOString().slice(0, 10))

  // 1. Branded Header Banner
  doc.setFillColor(...NAVY)
  doc.rect(0, 0, 210, 36, 'F')

  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(17)
  doc.text(propertyName.toUpperCase(), 18, 15)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(203, 213, 225)
  doc.text(`Managed by ${landlordCompany}`, 18, 22)
  doc.text(`${address} · ${landlordEmail} · ${landlordPhone}`, 18, 28)

  // Right Pill
  doc.setFillColor(...EMERALD)
  doc.roundedRect(132, 9, 60, 18, 2, 2, 'F')
  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.5)
  doc.text('TENANCY AGREEMENT', 162, 16, { align: 'center' })
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(7.8)
  doc.text(`Ref: ${lease.leaseNumber}`, 162, 22, { align: 'center' })

  let y = 45

  // Document Heading
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(13)
  doc.setTextColor(...NAVY)
  doc.text('RESIDENTIAL TENANCY AGREEMENT', 105, y, { align: 'center' })
  y += 5.5
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...TEXT_MUTED)
  doc.text(`Made under the Laws of the Republic of Kenya · Issued ${issueDate}`, 105, y, { align: 'center' })
  y += 8

  // 2. Parties & Premises Grid
  doc.setFillColor(...BG_LIGHT)
  doc.setDrawColor(...BORDER)
  doc.roundedRect(18, y, 84, 38, 2, 2, 'FD')
  doc.roundedRect(108, y, 84, 38, 2, 2, 'FD')

  // Left box: Landlord
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...EMERALD)
  doc.text('THE LANDLORD', 23, y + 7)
  doc.setFontSize(10)
  doc.setTextColor(...NAVY)
  doc.text(landlordCompany, 23, y + 14)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.3)
  doc.setTextColor(...TEXT_MUTED)
  doc.text(`Property: ${propertyName}`, 23, y + 20)
  doc.text(`Location: ${address}`, 23, y + 25.5)
  doc.text(`Contact: ${landlordEmail}`, 23, y + 31)

  // Right box: Tenant
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(...EMERALD)
  doc.text('THE TENANT (RESIDENT)', 113, y + 7)
  doc.setFontSize(10)
  doc.setTextColor(...NAVY)
  doc.text(residentName, 113, y + 14)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.3)
  doc.setTextColor(...TEXT_MUTED)
  doc.text(`ID / Passport: ${residentId}`, 113, y + 20)
  doc.text(`Phone: ${residentPhone}`, 113, y + 25.5)
  doc.text(`Email: ${residentEmail}`, 113, y + 31)

  y += 44

  // 3. Key Commercial Schedule Bar
  doc.setFillColor(...NAVY)
  doc.roundedRect(18, y, 174, 8, 1.5, 1.5, 'F')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.2)
  doc.setTextColor(255, 255, 255)
  doc.text('SCHEDULE OF TENANCY PARTICULARS', 23, y + 5.3)
  y += 8

  doc.setFillColor(255, 255, 255)
  doc.setDrawColor(...BORDER)
  doc.rect(18, y, 174, 29, 'FD')

  const drawScheduleRow = (label1: string, val1: string, label2: string, val2: string, rowY: number) => {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(7.8)
    doc.setTextColor(...TEXT_MUTED)
    doc.text(label1, 23, rowY)
    doc.text(label2, 111, rowY)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8.6)
    doc.setTextColor(...TEXT_DARK)
    doc.text(val1, 56, rowY)
    doc.text(val2, 145, rowY)
  }

  const endLabel = lease.endDate && String(lease.endDate).trim()
    ? formatHumanDate(lease.endDate)
    : 'Open-ended (Month-to-Month)'

  drawScheduleRow('Demised Unit:', `Unit ${unitNo} (${unitTypeLabel})`, 'Agreement No:', lease.leaseNumber, y + 6.5)
  drawScheduleRow('Lease Start:', formatHumanDate(lease.startDate), 'Lease End:', endLabel, y + 14.5)
  drawScheduleRow('Monthly Rent:', `${formatKES(lease.monthlyRent)} / month`, 'Rent Due Day:', `Day ${rentDueDay} of each month`, y + 22.5)
  y += 29

  doc.setFillColor(...BG_LIGHT)
  doc.rect(18, y, 174, 9, 'FD')
  drawScheduleRow('Security Deposit:', formatKES(lease.depositAmount), 'Deposit Status:', depositStatus, y + 6)
  y += 14

  // 4. Official Payment Channel & Anti-Fraud Notice Box
  doc.setFillColor(...AMBER_BG)
  doc.setDrawColor(...AMBER_BORDER)
  doc.roundedRect(18, y, 174, 20, 2, 2, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.3)
  doc.setTextColor(...NAVY)
  doc.text(`OFFICIAL PAYMENT CHANNEL — M-PESA PAY BILL: ${paybill}  |  ACCOUNT NO: ${accountNo}  (${landlordCompany})`, 23, y + 6.8)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...TEXT_DARK)
  doc.text(`Confirm the M-Pesa prompt displays ${landlordCompany} before entering your PIN.`, 23, y + 12)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7.8)
  doc.setTextColor(...AMBER)
  doc.text('NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.', 23, y + 17)
  y += 26

  // Helper to write numbered clauses with automatic page breaks
  const ensureSpace = (neededMm: number) => {
    if (y + neededMm > 274) {
      doc.addPage()
      y = 20
    }
  }

  const addClause = (num: string, title: string, body: string) => {
    const wrapped = doc.splitTextToSize(body, 170)
    const blockHeight = 6 + wrapped.length * 4.3 + 4
    ensureSpace(blockHeight)

    doc.setFont('helvetica', 'bold')
    doc.setFontSize(9.2)
    doc.setTextColor(...NAVY)
    doc.text(`${num}. ${title}`, 18, y)
    y += 4.8

    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8.6)
    doc.setTextColor(...TEXT_DARK)
    doc.text(wrapped, 20, y, { lineHeightFactor: 1.38 })
    y += wrapped.length * 4.3 + 4
  }

  // 5. Formal Legal Clauses
  addClause(
    '1',
    'DEMISED PREMISES & PERMITTED USE',
    `The Landlord lets and the Tenant takes residential Unit ${unitNo} (${unitTypeLabel}) situated at ${propertyName}, ${address}, together with standard fixtures and fittings. The premises shall be used strictly as a private residential dwelling by the Tenant and approved household members. The Tenant shall not sublet, assign, part with possession, or conduct any commercial or unlawful business on the premises without the Landlord's prior written consent.`
  )

  addClause(
    '2',
    'TERM & RENEWAL',
    lease.endDate && String(lease.endDate).trim()
      ? `This Tenancy shall commence on ${formatHumanDate(lease.startDate)} and continue for a fixed term expiring on ${formatHumanDate(lease.endDate)}, unless terminated earlier in accordance with Clause 7. Upon expiry of the fixed term, if the Tenant remains in occupation with the consent of the Landlord, the tenancy shall renew on a month-to-month basis under the same terms subject to any written rent review notice served at least thirty (30) days in advance.`
      : `This Tenancy shall commence on ${formatHumanDate(lease.startDate)} on an ongoing month-to-month basis until terminated by either party in accordance with Clause 7, subject to at least thirty (30) days written notice for any rent review.`
  )

  addClause(
    '3',
    'RENT & PAYMENT TERMS (RENT ONLY)',
    `The agreed monthly rent is ${formatKES(lease.monthlyRent)}, payable strictly in advance on or before Day ${rentDueDay} of each calendar month. The Landlord collects monthly rent and refundable security deposit only. All rent and deposit payments MUST be remitted solely through M-Pesa Pay Bill ${paybill}, Account Number ${accountNo} (${landlordCompany}), or via the verified STK Push prompt on the ${propertyName} Resident Portal. Electronic receipts are automatically issued upon reconciliation to this specific Lease (${lease.leaseNumber} — Unit ${unitNo}).`
  )

  addClause(
    '4',
    'SECURITY DEPOSIT',
    `The Tenant shall maintain a refundable Security Deposit of ${formatKES(lease.depositAmount)} (Current Status: ${depositStatus}) held by the Landlord as security against unpaid rent, lost keys/access cards, or damage beyond reasonable wear and tear. The Security Deposit shall NOT be applied by the Tenant toward the final month's rent without prior written approval. Subject to joint move-out inspection and clearance of rent arrears, the Landlord shall refund the balance of the deposit within thirty (30) days of vacant possession.`
  )

  addClause(
    '5',
    'UTILITIES, REPAIRS & MAINTENANCE',
    `Water, electricity, and internet/TV services are NOT collected by the Landlord and shall be paid directly by the Tenant to the respective service providers. The Tenant shall maintain the interior of Unit ${unitNo} in clean, tenantable condition. The Landlord shall maintain the structural integrity, roof, external walls, and shared building services. Any maintenance defect must be reported promptly through the ${propertyName} Resident Portal.`
  )

  addClause(
    '6',
    'HOUSE RULES & QUIET ENJOYMENT',
    `The Tenant covenants to observe the ${propertyName} Resident Handbook and House Rules, including maintaining quiet hours between 10:00 PM and 6:00 AM, disposing of domestic waste in designated areas, parking only in authorized bays, and refraining from structural alterations or nuisance to neighboring residents. Subject to punctual payment of rent and compliance with these covenants, the Landlord guarantees the Tenant peaceful and quiet enjoyment of Unit ${unitNo}.`
  )

  addClause(
    '7',
    'TERMINATION & NOTICE PERIOD',
    `Either party may terminate this Agreement by giving at least one (1) full calendar month's written notice prior to the intended vacate date. If the Tenant vacates without serving the requisite notice, one month's rent in lieu of notice shall be recoverable. Should rent remain unpaid for fourteen (14) days after becoming due, or in the event of a material breach of covenant that remains uncured after written notice, the Landlord may exercise lawful remedies including termination and re-entry in accordance with Kenyan law.`
  )

  const customTerms = (lease.terms || '').trim()
  const governingText = customTerms
    ? `Special Notes on File: ${customTerms}\n\nThis Agreement constitutes the entire understanding between the parties regarding Unit ${unitNo} and shall be governed by and construed in accordance with the Laws of the Republic of Kenya.`
    : `This Agreement constitutes the entire understanding between the parties regarding Unit ${unitNo} and shall be governed by and construed in accordance with the Laws of the Republic of Kenya.`

  addClause('8', 'SPECIAL COVENANTS & GOVERNING LAW', governingText)

  // 6. Formal Execution & Signature Block
  ensureSpace(64)
  y += 4
  doc.setDrawColor(...NAVY)
  doc.setLineWidth(0.4)
  doc.line(18, y, 192, y)
  y += 6

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9.5)
  doc.setTextColor(...NAVY)
  doc.text('IN WITNESS WHEREOF the parties have executed this Tenancy Agreement as of the dates stated below:', 18, y)
  y += 9

  // Two-column execution cards
  doc.setFillColor(...BG_LIGHT)
  doc.setDrawColor(...BORDER)
  doc.setLineWidth(0.2)
  doc.roundedRect(18, y, 83, 44, 2, 2, 'FD')
  doc.roundedRect(109, y, 83, 44, 2, 2, 'FD')

  // Landlord column
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.3)
  doc.setTextColor(...NAVY)
  doc.text('SIGNED FOR & ON BEHALF OF LANDLORD', 23, y + 7)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.2)
  doc.setTextColor(...TEXT_DARK)
  doc.text(landlordCompany, 23, y + 13)
  doc.text('Authorized Signatory: _______________________', 23, y + 24)
  doc.text('Name / Title: _______________________________', 23, y + 31)
  doc.text('Date & Stamp: ______________________________', 23, y + 38)

  // Tenant column
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.3)
  doc.setTextColor(...NAVY)
  doc.text('SIGNED BY THE TENANT (RESIDENT)', 114, y + 7)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.2)
  doc.setTextColor(...TEXT_DARK)
  doc.text(`${residentName} (ID: ${residentId})`, 114, y + 13)
  doc.text('Tenant Signature: ___________________________', 114, y + 24)
  doc.text('Witness Name: ______________________________', 114, y + 31)
  doc.text('Date: ______________________________________', 114, y + 38)

  addPageFooter(doc, `Lease ${lease.leaseNumber} · Unit ${unitNo}`, propertyName)
  return doc
}

export function downloadLeaseAgreementPdf(
  lease: Lease,
  tenant?: Tenant | null,
  unit?: Unit | null
) {
  const doc = generateLeaseAgreementPdf(lease, tenant, unit)
  const safeRef = (lease.leaseNumber || lease.id || 'Lease').replace(/[^A-Za-z0-9_-]/g, '')
  const safeUnit = (lease.unitNumber || unit?.unitNumber || 'Unit').replace(/[^A-Za-z0-9_-]/g, '')
  doc.save(`Lapis_Suites_Tenancy_Agreement_Unit_${safeUnit}_${safeRef}.pdf`)
}

export function downloadResidentHandbookPdf() {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4'
  })

  const propertyName = propertySettings.propertyName || 'Lapis Suites'
  const landlordCompany = propertySettings.paybillRecipientName || 'LAPIS APARTMENTS LIMITED'
  const paybill = propertySettings.paybillNumber || '522533'
  const accountNo = propertySettings.accountNumber || '8107578'
  const rentDueDay = propertySettings.rentDueDay || 5
  const contactEmail = propertySettings.contactEmail || 'lapissuites@gmail.com'
  const contactPhone = propertySettings.contactPhone || '+254 797 204 141'

  // Header
  doc.setFillColor(...NAVY)
  doc.rect(0, 0, 210, 34, 'F')
  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(17)
  doc.text(`${propertyName.toUpperCase()} — RESIDENT HANDBOOK`, 18, 15)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(203, 213, 225)
  doc.text(`House Rules, Payment Guidelines & Community Standards · ${landlordCompany}`, 18, 23)
  doc.text(`Management Support: ${contactEmail} · ${contactPhone}`, 18, 29)

  let y = 44

  // Official Payment Notice
  doc.setFillColor(...AMBER_BG)
  doc.setDrawColor(...AMBER_BORDER)
  doc.roundedRect(18, y, 174, 20, 2, 2, 'FD')
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.4)
  doc.setTextColor(...NAVY)
  doc.text(`OFFICIAL RENT PAYMENT — PAY BILL: ${paybill}  |  ACCOUNT NO: ${accountNo} (${landlordCompany})`, 23, y + 6.8)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...TEXT_DARK)
  doc.text(`Monthly rent is due on or before Day ${rentDueDay} of every calendar month. Always retain your M-Pesa receipt.`, 23, y + 12)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(7.8)
  doc.setTextColor(...AMBER)
  doc.text('NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.', 23, y + 17)
  y += 28

  const sections: Array<[string, string]> = [
    [
      '1. Rent Settlement & Multi-Unit Accounts',
      `Residents may pay rent directly via the Lapis Suites Mobile App or Web Portal (M-Pesa STK Push) or manually through M-Pesa Pay Bill ${paybill}, Account ${accountNo}. If you occupy more than one unit, select the specific unit in the Resident Portal before initiating payment so funds are reconciled strictly to that unit's lease.`
    ],
    [
      '2. Security, Access Control & Visitors',
      'All residents and visitors must observe gate and concierge sign-in procedures. Keys and access cards remain property of Lapis Apartments Limited and must not be duplicated without management approval. Report lost keys immediately for security re-keying.'
    ],
    [
      '3. Quiet Hours & Respectful Living',
      'Quiet hours are strictly observed daily from 10:00 PM to 6:00 AM. Keep audio devices, gatherings, and hallway conversations at considerate levels to respect fellow residents.'
    ],
    [
      '4. Maintenance & Repairs',
      'Log all plumbing, electrical, or fixture requests through the Maintenance tab on the Lapis Suites App or Web Portal for tracked dispatch. Emergency leaks or power hazards should also be called in immediately to Property Management.'
    ],
    [
      '5. Waste Disposal, Common Areas & Parking',
      'Bag all household refuse securely and place it in designated collection bins. Corridors, stairwells, and fire exits must remain unobstructed at all times. Vehicles must be parked strictly within marked resident bays.'
    ],
    [
      '6. Alterations, Subletting & Move-Out',
      'No permanent drilling, repainting, or subletting is permitted without prior written approval. A minimum of one (1) full calendar month written notice is required prior to vacating. Security deposits are reconciled and refunded within 30 days following joint move-out inspection and clearance of utility bills.'
    ]
  ]

  for (const [title, body] of sections) {
    const wrapped = doc.splitTextToSize(body, 170)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(9.5)
    doc.setTextColor(...NAVY)
    doc.text(title, 18, y)
    y += 5
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8.7)
    doc.setTextColor(...TEXT_DARK)
    doc.text(wrapped, 20, y, { lineHeightFactor: 1.4 })
    y += wrapped.length * 4.4 + 6
  }

  addPageFooter(doc, 'Resident Handbook & House Rules', propertyName)
  doc.save('Lapis_Suites_Resident_Handbook.pdf')
}
