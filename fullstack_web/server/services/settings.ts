import { getDb, isDbConnected } from "../db";
import {
  MAX_ADMIN_ACCOUNTS,
  isAllowedAdminEmail,
  normalizeKenyanPhone,
} from "../config";

export interface AppSettingsDoc {
  id: "property_settings";
  propertyName: string;
  address: string;
  city: string;
  totalFloors: number;
  managerName: string;
  contactPhone: string;
  contactEmail: string;
  paybillNumber: string;
  accountNumber: string;
  paybillRecipientName: string;
  currency: string;
  rentDueDay: number;
  gracePeriodDays: number;
  lateFeePercent: number;
  autoReconciliationEnabled: boolean;
  updatedAt: string;
}

export const DEFAULT_APP_SETTINGS: AppSettingsDoc = {
  id: "property_settings",
  propertyName: "LAPIS SUITES",
  address: "Unit Tower 4, Lapis Boulevard, Upper Hill",
  city: "Nairobi",
  totalFloors: 14,
  managerName: "Lapis Suites Management",
  contactPhone: "+254 700 892 110",
  contactEmail: "lapissuites@gmail.com",
  paybillNumber: "522533",
  accountNumber: "8107578",
  paybillRecipientName: "LAPIS APARTMENTS LIMITED",
  currency: "KES",
  rentDueDay: 5,
  gracePeriodDays: 5,
  lateFeePercent: 5,
  autoReconciliationEnabled: true,
  updatedAt: new Date().toISOString(),
};

export async function getAppSettings(): Promise<AppSettingsDoc> {
  if (!isDbConnected()) return { ...DEFAULT_APP_SETTINGS };
  const db = getDb();
  const existing = await db
    .collection("settings")
    .findOne({ id: "property_settings" }, { projection: { _id: 0 } });
  if (!existing) {
    const doc = {
      ...DEFAULT_APP_SETTINGS,
      updatedAt: new Date().toISOString(),
    };
    await db.collection("settings").insertOne({ ...doc });
    return doc;
  }
  return { ...DEFAULT_APP_SETTINGS, ...existing } as AppSettingsDoc;
}

export async function getRentDueDay(): Promise<number> {
  try {
    const settings = await getAppSettings();
    const day = Number(settings.rentDueDay);
    if (Number.isFinite(day) && day >= 1 && day <= 28) return Math.floor(day);
  } catch {}
  return 5;
}

export async function getAuthorizedAdminsFromDb(): Promise<
  Array<{
    id: string;
    name: string;
    email: string;
    phone: string;
    avatarInitials: string;
  }>
> {
  if (!isDbConnected()) return [];
  const db = getDb();
  const users = await db
    .collection("users")
    .find({ role: "landlord" }, { projection: { _id: 0, passwordHash: 0 } })
    .sort({ createdAt: 1, _id: 1 })
    .toArray();

  return users
    .filter((u: any) => isAllowedAdminEmail(u.email))
    .slice(0, MAX_ADMIN_ACCOUNTS)
    .map((u: any) => ({
      id: u.id,
      name: u.name || "Administrator",
      email: u.email,
      phone: u.phone ? normalizeKenyanPhone(u.phone) : "",
      avatarInitials: u.avatarInitials || "AD",
    }));
}
