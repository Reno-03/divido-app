<div align="center">
  <img src="assets/divido_logo.png" alt="Divido Logo" width="200" />
  <h1>Divido</h1>
  <p>
    A Flutter + Supabase Progressive Web App for tracking and splitting shared expenses across groups.
  </p>
</div>

<p align="center">
  <a href="https://flutter.dev/">
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  </a>
  <a href="https://supabase.com/">
    <img src="https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase&logoColor=white" alt="Supabase">
  </a>
  <a href="https://web.dev/progressive-web-apps/">
    <img src="https://img.shields.io/badge/PWA-Ready-5A0FC8" alt="PWA Ready">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT">
  </a>
  <img src="https://img.shields.io/badge/Version-v1.0.0-blueviolet" alt="Version">
</p>

<p align="center">
  Divido is a <strong>Flutter-powered Progressive Web App</strong> for tracking and splitting shared expenses
  with friends, family, or roommates.
  It uses <strong>Supabase</strong> for authentication, real-time data, and secure storage — and can be
  installed to your home screen on mobile or desktop as a PWA.
</p>

---

## ✨ Features

- **Authentication**
  - Username-based login backed by Supabase Auth
  - Registration with first name, last name, email, username, password, and a personal color
  - Circle avatar upload on registration and profile page
  - Terms and Conditions acceptance before account creation
  - Session restoration on app start (Remember Me via JWT)

- **Groups**
  - Create groups and invite members via a shareable 8-character invite code
  - Join groups using an invite code — no links or deep linking required
  - Group Info page showing photo, name, description, members, roles, and user colors
  - Edit group name, description, and photo as a member
  - Group creator Danger Zone — delete group or remove specific members
  - Group avatar visible in the home app bar for quick context
  - Balance pill on each group card showing your net owed/owing at a glance

- **Expense Management**
  - Create expenses with a title, description, and total amount
  - Split equally or set custom amounts per payer
  - All expenses scoped to the active group
  - Edit and delete expenses
  - Search expenses by title or date
  - Filter by paid/unpaid or your own involvement
  - Interactive expense cards with expandable details and hero animations

- **Payments & Balances**
  - Record payments as Cash or GCash
  - Net balance computed from expenses and payments per group
  - Nudge feature to remind members to settle up
  - Balance activity with per-member payment history
  - GCash number copyable directly from balance cards

- **Dashboard**
  - Live financial metrics: total group expense, your own share, owed to you, you owe
  - Week-over-week spending trends with percentage comparison
  - Summary of balances per member
  - Recent expenses and your top expenses this week
  - Group members list with creator highlighted
  - Personalized note/status card — tap to set or update your status
  - Breathing Divido logo using native Flutter animation

- **Profile**
  - Edit name, email, contact number, GCash number, and personal color
  - Upload and update circle avatar photo
  - Set a note/status visible to group members
  - All profile changes reflect instantly across the app

- **UI / UX**
  - Modern dark theme optimized for mobile and desktop
  - Shimmer loading states across all pages
  - Bottom navigation bar with docked FAB for quick expense creation
  - Consistent bottom modal sheet design throughout
  - Fallback empty states for all list pages
  - Changelog popup on first launch after an update

- **Security**
  - Row Level Security (RLS) policies on all Supabase tables
  - No API keys or internal URLs exposed in error output

- **PWA**
  - Installable via browser (standalone display mode)
  - Web manifest, icons, and favicon configured in `web/`

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x |
| Backend | Supabase (Auth, Database, Storage) |
| State Management | `provider` (`ExpenseProvider`, `GroupProvider`, `StatusProvider`) |
| Animations | Flutter `AnimationController` (breathing logo, hero transitions, shimmer) |
| Platform Targets | Web (PWA), Android, Windows, Linux |
| Deployment | Vercel (frontend) |
| Environment Config | `flutter_dotenv` via `assets/.env` |

---

## 🚀 Getting Started

### ✅ Prerequisites

- Flutter SDK (3.11.0 or compatible, as defined in `pubspec.yaml`)
- A Supabase project with the following tables set up:
  - `profiles`, `expenses`, `expense_breakdowns`, `payments`, `groups`, `group_members`
- Environment variables:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY`

### 1. Clone & Install Dependencies

```bash
git clone https://github.com/Reno-03/divido-app.git
cd divido_app
flutter pub get
```

### 2. Configure Environment Variables

Create the file `assets/.env` (already referenced in `pubspec.yaml`):

```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

### 3. Run the App

```bash
# Web (PWA)
flutter run -d chrome

# Android
flutter run -d android

# Windows
flutter run -d windows
```

---

## 📦 Building for Web / PWA

### Build

```bash
flutter build web --release
```

Output is generated in `build/web/` and includes all PWA assets (manifest, icons, service worker).

### Deploy

- A `vercel.json` is included — point Vercel to the `build/web` output directory.
- Compatible with any static hosting provider (Netlify, GitHub Pages, Firebase Hosting, etc.).

---

## 🧩 Development Notes

- Initial route is determined by whether there is an active Supabase auth session.
- `ExpenseProvider`, `GroupProvider`, and `StatusProvider` manage app-wide state via `ChangeNotifier`.
- All expenses, payments, and balances are scoped to the currently selected group.
- The app is designed primarily for portrait usage and touch devices but also supports mouse and trackpad inputs on desktop and web.

---

## 📄 License

This project includes a `LICENSE` file; see it for details on usage and redistribution.
