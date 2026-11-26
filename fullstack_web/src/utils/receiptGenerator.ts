import { jsPDF } from 'jspdf'
import type { Transaction, Tenant, Lease, TenantFinancialStanding } from '../types'
import { formatKES, formatHumanDate, formatHumanDateTime } from './formatters'

export function generateReceiptPdf(
  tx: Transaction,
  tenant?: Tenant | null,
  lease?: Lease | null,
  standing?: TenantFinancialStanding | null
): jsPDF {
  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'mm',
    format: 'a4'
  })

  // Colors
  const navy = [15, 23, 42] as const // #0f172a
  const teal = [13, 148, 136] as const // #0d9488
  const emerald = [5, 150, 105] as const // #059669
  const textDark = [30, 41, 59] as const // #1e293b
  const textMuted = [100, 116, 139] as const // #64748b
  const bgLight = [248, 250, 252] as const // #f8fafc
  const borderLight = [226, 232, 240] as const // #e2e8f0

  // 1. Header Banner
  doc.setFillColor(...navy)
  doc.rect(0, 0, 210, 36, 'F')

  // Brand Name
  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(18)
  doc.text('LAPIS SUITES', 18, 16)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(203, 213, 225)
  doc.text('Urban Executive Living · Automated Property Management', 18, 23)
  doc.text('Kileleshwa, Nairobi, Kenya · billing@lapissuites.com · +254 700 000 000', 18, 29)

  // Document Title Pill on Top Right
  doc.setFillColor(...teal)
  doc.roundedRect(138, 10, 54, 16, 2, 2, 'F')
  doc.setTextColor(255, 255, 255)
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.text('PAYMENT RECEIPT', 142, 17)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(7.5)
  doc.text(tx.reference || 'OFFICIAL COPY', 142, 22)

  // 2. Receipt Metadata Box
  doc.setFillColor(...bgLight)
  doc.setDrawColor(...borderLight)
  doc.roundedRect(18, 44, 174, 24, 2, 2, 'FD')

  doc.setFontSize(8)
  doc.setTextColor(...textMuted)
  doc.text('RECEIPT NUMBER', 24, 52)
  doc.text('DATE & TIME', 72, 52)
  doc.text('PAYMENT METHOD', 120, 52)
  doc.text('STATUS', 162, 52)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9.5)
  doc.setTextColor(...textDark)
  doc.text(tx.reference || 'N/A', 24, 60)
  doc.text(formatHumanDate(tx.date) || tx.timestamp?.slice(0, 10) || 'N/A', 72, 60)
  doc.text((tx.method || 'M-Pesa').toUpperCase().replace('_', ' '), 120, 60)

  doc.setTextColor(...emerald)
  doc.text('VERIFIED', 162, 60)

  // 3. Resident & Unit Breakdown (Two Column Cards)
  // Left: Resident Info
  doc.setFillColor(...bgLight)
  doc.setDrawColor(...borderLight)
  doc.roundedRect(18, 74, 84, 38, 2, 2, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.5)
  doc.setTextColor(...teal)
  doc.text('RECEIVED FROM', 24, 82)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(11)
  doc.setTextColor(...navy)
  doc.text(tenant?.name || tx.tenantName || tx.payerName || 'Resident', 24, 90)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...textMuted)
  doc.text(`Phone: ${tenant?.phone || tx.phoneNumber || 'On file'}`, 24, 97)
  doc.text(`Email: ${tenant?.email || 'billing@lapissuites.com'}`, 24, 104)

  // Right: Unit & Tenancy Info
  doc.setFillColor(...bgLight)
  doc.roundedRect(108, 74, 84, 38, 2, 2, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.5)
  doc.setTextColor(...teal)
  doc.text('PROPERTY & PREMISES', 114, 82)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(11)
  doc.setTextColor(...navy)
  doc.text(`Unit ${tx.unitNumber || tenant?.currentUnitNumber || lease?.unitNumber || 'Unassigned'}`, 114, 90)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...textMuted)
  doc.text(`Unit Type: ${lease?.unitType || 'Apartment Suite'}`, 114, 97)
  doc.text(`Lease Number: ${lease?.leaseNumber || tx.leaseId || 'Standard Tenancy'}`, 114, 104)

  // 4. Line Items Table
  let startY = 120
  doc.setFillColor(...navy)
  doc.rect(18, startY, 174, 9, 'F')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8.5)
  doc.setTextColor(255, 255, 255)
  doc.text('ITEM DESCRIPTION', 24, startY + 6)
  doc.text('CATEGORY', 114, startY + 6)
  doc.text('AMOUNT (KES)', 162, startY + 6)

  // Row 1: Payment Remittance
  startY += 9
  doc.setFillColor(255, 255, 255)
  doc.setDrawColor(...borderLight)
  doc.rect(18, startY, 174, 18, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9.5)
  doc.setTextColor(...navy)
  const itemDesc = tx.notes || `Rent remittance for Unit ${tx.unitNumber || tenant?.currentUnitNumber || 'Suite'}`
  doc.text(itemDesc.slice(0, 48), 24, startY + 8)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...textMuted)
  doc.text(`Transaction Reference: ${tx.reference || 'Verified'} · Verified via M-Pesa Gateway`, 24, startY + 14)

  doc.text((tx.category || 'Rent').toUpperCase(), 114, startY + 8)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(10)
  doc.setTextColor(...navy)
  doc.text(formatKES(tx.amount || 0), 162, startY + 9)

  // 5. Total Paid Summary Banner
  startY += 24
  doc.setFillColor(...bgLight)
  doc.roundedRect(108, startY, 84, 26, 2, 2, 'FD')

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...textMuted)
  doc.text('TOTAL AMOUNT PAID', 114, startY + 9)

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(14)
  doc.setTextColor(...emerald)
  doc.text(formatKES(tx.amount || 0), 114, startY + 19)

  // 6. Account Credit & Next Month Reconciliation Info
  startY += 34
  doc.setFillColor(240, 253, 250) // light teal
  doc.setDrawColor(153, 246, 228) // teal border
  doc.roundedRect(18, startY, 174, 30, 2, 2, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(9)
  doc.setTextColor(...teal)
  doc.text('ACCOUNT RECONCILIATION & ADVANCE CREDIT STATUS', 24, startY + 8)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(...textDark)

  const creditVal = standing ? standing.accountCredit : 0
  if (creditVal > 0) {
    doc.text(`Current Account Credit: ${formatKES(creditVal)} (Prepaid Advance Rent)`, 24, startY + 15)
    doc.setFontSize(8)
    doc.setTextColor(...textMuted)
    doc.text('• Automatic Reconciliation: This excess balance is safely stored as prepaid credit.', 24, startY + 21)
    doc.text('• When next month\'s billing is generated, rent will automatically be deducted from your credit.', 24, startY + 26)
  } else {
    doc.text(`Account Status: Settled · No outstanding arrears.`, 24, startY + 15)
    doc.setFontSize(8)
    doc.setTextColor(...textMuted)
    doc.text('• Next regular billing cycle commences on the 1st of next month.', 24, startY + 22)
  }

  // 7. Official Seal & Sign-off Footer
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(...textMuted)
  doc.text('Authorized by: Lapis Suites Property Management & Financial Operations', 18, 258)
  doc.text('This is a verified, digitally generated document. No physical stamp is required for legal validity.', 18, 263)

  doc.setDrawColor(...borderLight)
  doc.line(18, 268, 192, 268)

  doc.setFontSize(7.5)
  doc.text(`Generated: ${formatHumanDateTime(new Date().toISOString())} · Verification ID: ${tx.id || tx.reference}`, 18, 274)
  doc.text('Page 1 of 1', 176, 274)

  return doc
}

export function downloadReceiptPdf(
  tx: Transaction,
  tenant?: Tenant | null,
  lease?: Lease | null,
  standing?: TenantFinancialStanding | null
): void {
  const doc = generateReceiptPdf(tx, tenant, lease, standing)
  const filename = `Receipt_${tx.reference || tx.id}_${tx.unitNumber || 'Unit'}.pdf`
  doc.save(filename)
}

export function printReceiptPdf(
  tx: Transaction,
  tenant?: Tenant | null,
  lease?: Lease | null,
  standing?: TenantFinancialStanding | null
): void {
  const doc = generateReceiptPdf(tx, tenant, lease, standing)
  const blob = doc.output('blob')
  const blobUrl = URL.createObjectURL(blob)
  const printWindow = window.open(blobUrl, '_blank')
  if (printWindow) {
    printWindow.focus()
  }
}
