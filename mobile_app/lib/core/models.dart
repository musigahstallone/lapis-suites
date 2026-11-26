// Domain models & clean formatting helpers synced with the Lapis Suites backend API.

const Map<String, String> _categoryLabels = {
  'plumbing': 'Plumbing & Water',
  'electrical': 'Electrical & Lighting',
  'hvac': 'HVAC & Air Conditioning',
  'appliance': 'Appliances & Fixtures',
  'carpentry': 'Carpentry & Cabinetry',
  'internet': 'Internet & Intercom',
  'general': 'General Facilities',
};

String formatStatusLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Pending';
  return raw
      .trim()
      .split(RegExp(r'[_\s-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

String formatCategoryLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'General';
  final key = raw.trim().toLowerCase();
  return _categoryLabels[key] ?? formatStatusLabel(raw);
}

String formatPriorityLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Medium';
  return formatStatusLabel(raw);
}

String formatUnitTypeLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Suite';
  return raw
      .trim()
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

String formatPaymentMethodLabel(String? raw) {
  final m = (raw ?? '').toLowerCase();
  if (m.contains('stk')) return 'M-Pesa STK Push';
  if (m.contains('paybill')) return 'M-Pesa Paybill';
  if (m.contains('bank')) return 'Bank Transfer';
  if (m.contains('cash')) return 'Cash';
  return formatStatusLabel(raw);
}

/// Extract the 9 digits following +254 / 254 / 0 for Kenya mobile inputs
String extractKenyaNineDigits(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('254') && digits.length >= 12) {
    return digits.substring(3, 12);
  }
  if (digits.startsWith('0') && digits.length >= 10) {
    return digits.substring(1, 10);
  }
  if (digits.length > 9) return digits.substring(digits.length - 9);
  return digits;
}

/// Normalize 9 digits (or full local string) to canonical 2547XXXXXXXX format
String toCanonicalKenyaPhone(String raw) {
  final nine = extractKenyaNineDigits(raw);
  if (nine.length == 9 && (nine.startsWith('7') || nine.startsWith('1'))) {
    return '254$nine';
  }
  return raw.replaceAll(RegExp(r'\D'), '');
}

/// Clean local Kenyan phone formatting: 0703 438 444
String formatKenyanPhoneDisplay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final nine = extractKenyaNineDigits(raw);
  if (nine.length == 9) {
    return '0${nine.substring(0, 3)} ${nine.substring(3, 6)} ${nine.substring(6, 9)}';
  }
  return raw.trim();
}

/// Time-of-day greeting for SliverAppBar headers
String greetingForTimeOfDay() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Extract clean first name for greeting header
String firstNameFrom(String? raw, {String fallback = 'there'}) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isEmpty) return fallback;
  final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  return parts.isNotEmpty ? parts.first : fallback;
}

String currentMonthYearLabel() {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final now = DateTime.now();
  return '${months[now.month - 1]} ${now.year}';
}

String formatShortDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = DateTime.tryParse(raw.trim().replaceAll(' ', 'T'));
  if (parsed == null) {
    return raw.length > 16 ? raw.substring(0, 16) : raw;
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

/// Joins date and 12-hour time cleanly: "26 Nov 2026 · 02:15 PM"
String formatDateTimeDisplay(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final trimmed = raw.trim();
  final parsed = DateTime.tryParse(trimmed.contains('T') ? trimmed : trimmed.replaceAll(' ', 'T'));
  if (parsed == null) return formatShortDate(trimmed);
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final day = local.day.toString().padLeft(2, '0');
  final datePart = '$day ${months[local.month - 1]} ${local.year}';
  final hasTime = trimmed.contains(':');
  if (!hasTime) return datePart;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  final hr12 = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$datePart · $hr12:$min $ampm';
}

class UnitModel {
  final String id;
  final String unitNumber;
  final String type;
  final String status;
  final String? currentTenantId;
  final String? currentTenantName;
  final String? currentLeaseId;
  final int monthlyRent;
  final List<String> features;

  const UnitModel({
    required this.id,
    required this.unitNumber,
    required this.type,
    required this.status,
    this.currentTenantId,
    this.currentTenantName,
    this.currentLeaseId,
    required this.monthlyRent,
    this.features = const [],
  });

  bool get isOccupied => status.toLowerCase() == 'occupied';

  factory UnitModel.fromJson(Map<String, dynamic> json, [List<UnitTypeModel>? unitTypes]) {
    final typeKey = (json['type'] ?? '').toString();
    int rent = 0;
    if (json['monthlyRent'] != null) {
      rent = (json['monthlyRent'] as num).toInt();
    } else if (unitTypes != null) {
      final match = unitTypes.firstWhere(
        (t) =>
            t.key.toLowerCase() == typeKey.toLowerCase() ||
            t.name.toLowerCase() == typeKey.toLowerCase(),
        orElse: () => const UnitTypeModel(id: '', key: '', name: '', baseRent: 35000),
      );
      rent = match.baseRent;
    } else {
      rent = typeKey == 'two-bedroom'
          ? 75000
          : (typeKey == 'one-bedroom' ? 50000 : 35000);
    }

    return UnitModel(
      id: json['id']?.toString() ?? '',
      unitNumber: json['unitNumber']?.toString() ?? 'N/A',
      type: typeKey,
      status: json['status']?.toString() ?? 'vacant',
      currentTenantId: json['currentTenantId']?.toString(),
      currentTenantName: json['currentTenantName']?.toString(),
      currentLeaseId: json['currentLeaseId']?.toString(),
      monthlyRent: rent,
      features: (json['features'] as List?)?.map((e) => e.toString()).toList() ??
          const ['High Speed Fibre', 'Backup Generator', 'Biometric Access'],
    );
  }
}

class TenantModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String nationalId;
  final String? currentUnitId;
  final String currentUnitNumber;
  final String? currentLeaseId;
  final int balance;
  final int arrearsBalance;
  final int accountCredit;
  final String nextPaymentDueDate;
  final String status;
  final String avatarInitials;

  const TenantModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.nationalId,
    this.currentUnitId,
    required this.currentUnitNumber,
    this.currentLeaseId,
    required this.balance,
    required this.arrearsBalance,
    required this.accountCredit,
    required this.nextPaymentDueDate,
    required this.status,
    required this.avatarInitials,
  });

  bool get hasCredit => accountCredit > 0;
  bool get hasArrears => arrearsBalance > 0 || balance > 0;
  int get effectiveBalanceDue => balance > 0 ? balance : arrearsBalance;

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    final rawName = json['name']?.toString() ?? 'Resident';
    final initials = json['avatarInitials']?.toString() ??
        (rawName.isNotEmpty
            ? rawName
                .split(' ')
                .map((p) => p.isNotEmpty ? p[0] : '')
                .join('')
                .toUpperCase()
            : 'TN');

    return TenantModel(
      id: json['id']?.toString() ?? '',
      name: rawName,
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      nationalId: json['nationalId']?.toString() ?? '',
      currentUnitId: json['currentUnitId']?.toString(),
      currentUnitNumber: json['currentUnitNumber']?.toString() ?? '',
      currentLeaseId: json['currentLeaseId']?.toString(),
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      arrearsBalance: (json['arrearsBalance'] as num?)?.toInt() ?? 0,
      accountCredit: (json['accountCredit'] as num?)?.toInt() ?? 0,
      nextPaymentDueDate: json['nextPaymentDueDate']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      avatarInitials: initials.length > 2 ? initials.substring(0, 2) : initials,
    );
  }
}

class LeaseModel {
  final String id;
  final String leaseNumber;
  final String tenantId;
  final String tenantName;
  final String unitId;
  final String unitNumber;
  final String unitType;
  final String startDate;
  final String endDate;
  final int monthlyRent;
  final int depositAmount;
  final bool depositPaid;
  final String depositStatus;
  final String status;
  final String terms;
  final String nextPaymentDueDate;

  const LeaseModel({
    required this.id,
    required this.leaseNumber,
    required this.tenantId,
    required this.tenantName,
    required this.unitId,
    required this.unitNumber,
    required this.unitType,
    required this.startDate,
    required this.endDate,
    required this.monthlyRent,
    required this.depositAmount,
    required this.depositPaid,
    required this.depositStatus,
    required this.status,
    required this.terms,
    required this.nextPaymentDueDate,
  });

  bool get isActive =>
      status.toLowerCase() == 'active' || status.toLowerCase() == 'pending_deposit';
  bool get isDepositSettled => depositPaid || depositStatus.toLowerCase() == 'paid';

  factory LeaseModel.fromJson(Map<String, dynamic> json) {
    return LeaseModel(
      id: json['id']?.toString() ?? '',
      leaseNumber: json['leaseNumber']?.toString() ?? json['id']?.toString() ?? 'LPS',
      tenantId: json['tenantId']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? 'Resident',
      unitId: json['unitId']?.toString() ?? '',
      unitNumber: json['unitNumber']?.toString() ?? '',
      unitType: json['unitType']?.toString() ?? 'Suite',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      monthlyRent: (json['monthlyRent'] as num?)?.toInt() ?? 0,
      depositAmount: (json['depositAmount'] as num?)?.toInt() ?? 0,
      depositPaid: json['depositPaid'] == true,
      depositStatus:
          json['depositStatus']?.toString() ?? (json['depositPaid'] == true ? 'paid' : 'pending'),
      status: json['status']?.toString() ?? 'active',
      terms: json['terms']?.toString() ?? 'Standard residential tenancy agreement.',
      nextPaymentDueDate: json['nextPaymentDueDate']?.toString() ?? '',
    );
  }
}

class TransactionModel {
  final String id;
  final String reference;
  final String invoiceRef;
  final String? tenantId;
  final String? tenantName;
  final String? unitNumber;
  final int amount;
  final String date;
  final String timestamp;
  final String method;
  final String source;
  final String status;
  final String category;
  final String? phoneNumber;
  final String? payerName;
  final String notes;
  final bool reconciled;

  const TransactionModel({
    required this.id,
    required this.reference,
    required this.invoiceRef,
    this.tenantId,
    this.tenantName,
    this.unitNumber,
    required this.amount,
    required this.date,
    required this.timestamp,
    required this.method,
    required this.source,
    required this.status,
    required this.category,
    this.phoneNumber,
    this.payerName,
    required this.notes,
    required this.reconciled,
  });

  bool get isMpesa =>
      method.toLowerCase().contains('mpesa') || method.toLowerCase().contains('stk');
  bool get isPendingVerification => status.toLowerCase() == 'pending_verification';
  bool get needsApproval =>
      !reconciled || isPendingVerification || status.toLowerCase() == 'unassigned';
  String get statusDisplayLabel {
    if (reconciled || status.toLowerCase() == 'reconciled') return 'Reconciled';
    if (isPendingVerification) return 'Pending Verification';
    if (status.toLowerCase() == 'unassigned') return 'Unassigned';
    return formatStatusLabel(status);
  }

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? json['id']?.toString() ?? 'REF',
      invoiceRef: json['invoiceRef']?.toString() ?? '',
      tenantId: json['tenantId']?.toString(),
      tenantName: json['tenantName']?.toString() ?? json['payerName']?.toString(),
      unitNumber: json['unitNumber']?.toString() ?? json['billRefNumber']?.toString(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      date: json['date']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      method: json['method']?.toString() ?? 'stk_push',
      source: json['source']?.toString() ?? 'api',
      status: json['status']?.toString() ?? 'reconciled',
      category: json['category']?.toString() ?? 'rent',
      phoneNumber: json['phoneNumber']?.toString(),
      payerName: json['payerName']?.toString(),
      notes: json['notes']?.toString() ?? '',
      reconciled: json['reconciled'] == true || json['status'] == 'reconciled',
    );
  }
}

class MaintenanceTicket {
  final String id;
  final String? tenantId;
  final String tenantName;
  final String? unitId;
  final String unitNumber;
  final String category;
  final String priority;
  final String title;
  final String description;
  final String status;
  final String? assignedTo;
  final String? resolutionNotes;
  final String? resolvedAt;
  final String createdAt;

  const MaintenanceTicket({
    required this.id,
    this.tenantId,
    required this.tenantName,
    this.unitId,
    required this.unitNumber,
    required this.category,
    required this.priority,
    required this.title,
    required this.description,
    required this.status,
    this.assignedTo,
    this.resolutionNotes,
    this.resolvedAt,
    required this.createdAt,
  });

  factory MaintenanceTicket.fromJson(Map<String, dynamic> json) {
    return MaintenanceTicket(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenantId']?.toString(),
      tenantName: json['tenantName']?.toString() ?? 'Resident',
      unitId: json['unitId']?.toString(),
      unitNumber: json['unitNumber']?.toString() ?? '',
      category: json['category']?.toString() ?? 'general',
      priority: json['priority']?.toString() ?? 'medium',
      title: json['title']?.toString() ?? 'Maintenance Request',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      assignedTo: json['assignedTo']?.toString(),
      resolutionNotes: json['resolutionNotes']?.toString(),
      resolvedAt: json['resolvedAt']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class UnitTypeModel {
  final String id;
  final String key;
  final String name;
  final int baseRent;
  final int depositMultiplier;
  final String description;
  final List<String> features;
  final int unitCount;
  final int occupiedCount;

  const UnitTypeModel({
    required this.id,
    required this.key,
    required this.name,
    required this.baseRent,
    this.depositMultiplier = 1,
    this.description = '',
    this.features = const [],
    this.unitCount = 0,
    this.occupiedCount = 0,
  });

  bool get hasOccupiedUnits => occupiedCount > 0;
  bool get hasAnyUnits => unitCount > 0;

  factory UnitTypeModel.fromJson(Map<String, dynamic> json) {
    return UnitTypeModel(
      id: json['id']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Suite',
      baseRent: (json['baseRent'] as num?)?.toInt() ?? 35000,
      depositMultiplier: (json['depositMultiplier'] as num?)?.toInt() ?? 1,
      description: json['description']?.toString() ?? '',
      features: (json['features'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      unitCount: (json['unitCount'] as num?)?.toInt() ?? 0,
      occupiedCount: (json['occupiedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class PropertySettingsModel {
  final String propertyName;
  final String paybillNumber;
  final String accountNumber;
  final String paybillRecipientName;
  final int rentDueDay;
  final int gracePeriodDays;
  final int lateFeePercent;
  final String contactPhone;
  final String contactEmail;

  const PropertySettingsModel({
    this.propertyName = 'LAPIS SUITES',
    this.paybillNumber = '522533',
    this.accountNumber = '8107578',
    this.paybillRecipientName = 'LAPIS APARTMENTS LIMITED',
    this.rentDueDay = 5,
    this.gracePeriodDays = 5,
    this.lateFeePercent = 5,
    this.contactPhone = '',
    this.contactEmail = '',
  });

  factory PropertySettingsModel.fromJson(Map<String, dynamic> json) {
    return PropertySettingsModel(
      propertyName: json['propertyName']?.toString() ?? 'LAPIS SUITES',
      paybillNumber: json['paybillNumber']?.toString() ?? '522533',
      accountNumber: json['accountNumber']?.toString() ?? '8107578',
      paybillRecipientName: json['paybillRecipientName']?.toString() ?? 'LAPIS APARTMENTS LIMITED',
      rentDueDay: (json['rentDueDay'] as num?)?.toInt() ?? 5,
      gracePeriodDays: (json['gracePeriodDays'] as num?)?.toInt() ?? 5,
      lateFeePercent: (json['lateFeePercent'] as num?)?.toInt() ?? 5,
      contactPhone: json['contactPhone']?.toString() ?? '',
      contactEmail: json['contactEmail']?.toString() ?? '',
    );
  }
}

class AdminAccountModel {
  final String id;
  final String name;
  final String email;
  final String phone;

  const AdminAccountModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });

  factory AdminAccountModel.fromJson(Map<String, dynamic> json) {
    return AdminAccountModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Administrator',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}

class DashboardData {
  final List<UnitModel> units;
  final List<TenantModel> tenants;
  final List<LeaseModel> leases;
  final List<TransactionModel> transactions;
  final List<UnitTypeModel> unitTypes;

  const DashboardData({
    required this.units,
    required this.tenants,
    required this.leases,
    required this.transactions,
    required this.unitTypes,
  });

  int get totalRentRoll => leases
      .where((l) => l.isActive)
      .fold(0, (sum, l) => sum + l.monthlyRent);
  int get totalArrears => tenants.fold(0, (sum, t) => sum + t.effectiveBalanceDue);
  int get totalCredits => tenants.fold(0, (sum, t) => sum + t.accountCredit);
  int get occupiedUnits => units.where((u) => u.isOccupied).length;
  double get occupancyRate => units.isEmpty ? 0 : (occupiedUnits / units.length) * 100;

  /// Reconciled rent collected in the current calendar month (YYYY-MM)
  int get collectedThisMonth {
    final now = DateTime.now();
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return transactions
        .where((tx) => tx.reconciled && (tx.date.startsWith(ym) || tx.timestamp.startsWith(ym)))
        .fold(0, (sum, tx) => sum + tx.amount);
  }

  /// Ratio (0.0 .. 1.0) of monthly rent collected vs expected rent roll
  double get collectionProgress {
    if (totalRentRoll <= 0) return 0.0;
    return (collectedThisMonth / totalRentRoll).clamp(0.0, 1.0);
  }
}

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type;
  final String timestamp;
  final bool read;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.read,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      timestamp: json['timestamp']?.toString() ?? json['createdAt']?.toString() ?? '',
      read: json['read'] == true,
    );
  }
}
