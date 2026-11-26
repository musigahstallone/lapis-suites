# Lapis Suites — Master Monorepo & Project Hub

Unified workspace containing all components for **Lapis Suites Property Management Platform**:
- **Backend API Server (Node.js / Express / TypeScript)**
- **Web Frontend (Vue 3 / Vite)**
- **Combined Fullstack Workspace (Development & Production Deployment)**
- **Cross-Platform Mobile Application (Flutter for Android & iOS)**

---

## Directory Structure

```
D:\QMUS\Lapis_Suites\
├── server\             # Standalone Backend API (Express + TypeScript + SQLite/MongoDB)
│   ├── server\         # Routes, Middleware, DB Config
│   ├── server.ts       # Express server entry point (Port 3001)
│   ├── seed.ts         # Database seeder
│   ├── .data\          # Local database storage
│   └── package.json
│
├── frontend\           # Standalone Web Application (Vue 3 + Vite)
│   ├── src\            # Views, Components, Router, Assets
│   ├── dist\           # Pre-built production bundle
│   ├── index.html
│   ├── vite.config.js  # Vite config with proxy to :3001
│   └── package.json
│
├── fullstack_web\      # Unified Node.js Web Monorepo (Dev Server + API combined)
│   ├── server\         # Backend routes & controllers
│   ├── src\            # Frontend Vue single-page application
│   ├── Dockerfile      # Containerization recipe
│   ├── docker-compose.yml
│   └── ecosystem.config.cjs
│
└── mobile_app\         # Flutter Mobile App (Android & iOS)
    ├── lib\            # Mobile application codebase (Orbix + HoPOn design)
    │   ├── auth\       # Independent Login Page (Direct role-based routing)
    │   ├── core\       # API Client, Models, Bottom Sheets, Vector Logo, Theme
    │   ├── landlord\   # Landlord Dashboard & Portfolio Overview
    │   ├── resident\   # Resident Portal (Rent, STK Push, Maintenance)
    │   └── pages\      # Dedicated detail pages (Tenant, Lease, Unit, Profile)
    ├── android\        # Android native module & manifest with network security
    └── build\app\outputs\flutter-apk\
        └── app-release.apk  # Ready-to-install Production Release APK (49.0 MB)
```

---

## Running the Components

### 1. Full-Stack Web Development (Quickstart)
Navigate to `fullstack_web\`:
```powershell
cd D:\QMUS\Lapis_Suites\fullstack_web
npm install
# Run API backend (Port 3001)
npm run server
# In another terminal, run frontend dev server (Port 5173 with proxy)
npm run dev
```

### 2. Backend Server Only
```powershell
cd D:\QMUS\Lapis_Suites\server
npm install
npm run server
```
- API Base URL: `http://localhost:3001/api`
- Production Cloudflare Tunnel: `https://suites.qmusglobal.com/api`

### 3. Frontend Web Only
```powershell
cd D:\QMUS\Lapis_Suites\frontend
npm install
npm run dev
```

### 4. Flutter Mobile App
```powershell
cd D:\QMUS\Lapis_Suites\mobile_app
flutter pub get

# Run on connected device or emulator:
flutter run

# Build Release APK:
flutter build apk
```
- Pre-built APK Location:
  `D:\QMUS\Lapis_Suites\mobile_app\build\app\outputs\flutter-apk\app-release.apk`
- Default Backend Target: `https://suites.qmusglobal.com/api` (Configured with offline fallback detection & live STK polling).

---

## Mobile App Highlights
- **Design System:** Orbix Studio minimalist layout + HoPOn color hierarchy (60% `#FAFAFA`, 30% `#FFFFFF`, 10% `#18181B` & pastel accent pills).
- **Typography:** Pure Google Sans (`GoogleFonts.plusJakartaSans`).
- **Realtime STK Experience:** Step-by-step STK push modal with animated indicators and non-blocking background callback polling.
- **Dedicated Flow Architecture:**
  - High-level entities (Tenant details, Lease details, Unit details, Profile settings) live in dedicated smooth pages with sticky Sliver AppBars.
  - Quick transactional actions (Payments received, STK push triggers, Unit creation) live in sleek bottom sheets.
- **Security & Scope:** Secure JWT storage in encrypted storage, tenant-scoped data queries (no unnecessary portfolio metrics fetched for tenants), and comprehensive role-based access.
