# Changelog

All notable changes to **Divido** will be documented in this file.

Divido is a Flutter-based Progressive Web App (PWA) for splitting and tracking shared expenses, powered by Supabase.

This project follows [Semantic Versioning](https://semver.org/).


## [0.2.0-beta] — 2026-02-24

### 🔐 Security
- Eliminated plaintext password storage.
- Migrated authentication to Supabase Auth with secure password hashing.
- Implemented JWT-based session management with secure persistence.

### ✨ Added
- Persistent login sessions across app restarts.
- Email-based user registration.
- Proper logout functionality that clears local session data.

### 💥 Breaking Changes
- Replaced legacy `users` table with `profiles` linked to `auth.users`.
- Updated foreign key relationships:
  - `expenses`
  - `expense_breakdowns`
  - `payments`
  now reference `profiles(id)`.
- Refactored authentication flow:
  - Login now uses `supabase.auth.signInWithPassword()`.
  - Registration now uses `supabase.auth.signUp()`.

### 🔧 Internal
- Migrated 4 existing users to Supabase Auth.
- Preserved all expense and payment records during migration.
- Refactored authentication logic to remove manual password validation.



## [0.1.0-beta] — 2026-02-21

### 🎉 First Beta Release

Initial pre-release version of Divido with core expense splitting and balance tracking functionality.

### ✨ Added

#### Expense Management
- Create expenses with title and total amount.
- Split expenses equally or with custom per-user amounts.
- View all expenses or only personal expenses ("Mine").
- Mark expenses as paid or unpaid with visual indicators.
- Date-grouped expense listings.

#### Balance Tracking
- Real-time net balance calculations between users.
- Clear indication of who owes you and who you owe.
- Record payments with optional notes.
- One-click settlement for exact balances.
- Color-coded balance indicators:
  - Green → owed to you
  - Red → you owe

#### User Experience
- Custom dark theme UI (`#171A3F`).
- Color-coded user avatars with initials.
- Three-tab navigation: **All**, **Mine**, **Balance**.
- Pull-to-refresh on all primary views.
- Responsive layout with smooth animations.

#### Authentication & Data
- Username/password authentication.
- User registration flow.
- Real-time data synchronization via Supabase.
- Persistent user session handling.

---
