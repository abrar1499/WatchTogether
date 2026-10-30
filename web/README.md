# Pocket AI

A chat-first personal expense manager with a Next.js web app, installable PWA, and Android WebView companion.

## Stack
- Next.js 15, React 19, TypeScript, Tailwind CSS
- Supabase Auth + PostgreSQL with Row Level Security
- Server-side command validation and allowlisted database actions
- Groq, OpenAI and xAI provider adapters (OpenAI-compatible chat completions API)
- AES-256-GCM encryption for user-supplied AI provider credentials
- Installable PWA and Android WebView shell

## Run locally
1. Install Node.js 20+.
2. From this directory run `npm install`.
3. Copy `.env.example` to `.env.local`.
4. Configure the Supabase variables described below.
5. Run `npm run dev` and open http://localhost:3000.

## Supabase setup
1. Create a Supabase project.
2. In SQL Editor, run `supabase/migrations/0001_initial_schema.sql`.
3. Enable Email auth in Authentication → Providers.
4. Set `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY`.
5. Set `SUPABASE_SERVICE_ROLE_KEY` server-side only. Never prefix it with NEXT_PUBLIC.
6. Generate a random 32-byte encryption key and set `CREDENTIALS_ENCRYPTION_KEY` server-side only. Example: `openssl rand -hex 32`.

The migration creates a Cash account and starter categories when a new user signs up. Financial tables are protected by owner-scoped RLS. The AI credentials table has no authenticated-user policies; only server routes use the service-role key to read/write encrypted credentials.

## AI providers
Open Settings → AI & app settings. Choose Groq, OpenAI, or xAI, paste an API key and model ID, and connect. The server validates the key against the provider's models endpoint before encrypting it with AES-256-GCM. The browser never receives stored credentials. Remove the key from the same screen at any time.

Suggested model IDs:
- Groq: `llama-3.3-70b-versatile`
- OpenAI: `gpt-4.1-mini`
- xAI: `grok-3-mini`

AI is optional. Common commands are parsed locally/server-side and manual entry remains available without a provider key.

## Android
The native Android project is a small WebView shell for the same hosted web app. Set the GitHub Actions secret `WEB_APP_URL` to the deployed HTTPS URL, then run the Build Pocket AI Android workflow. Without that secret, the APK displays a setup screen. The PWA can also be installed directly from Chrome on Android.

## Demo mode
Demo mode is local-only and stores sample/demo records in this browser's localStorage. It does not connect to Supabase and does not store AI keys. Do not enter real financial data in demo mode.

## Current command coverage
Add income/expenses, create accounts and categories, rename accounts, set opening balances, transfer between accounts, edit/delete the last transaction, list transactions, summaries, budgets, and guarded month-wide deletion. Unrecognized natural-language requests are sent to the configured provider for strict JSON intent parsing; all resulting actions are schema-validated and executed through allowlisted server code.

## Production checklist
- Deploy the web app to a Node-compatible host (for example, Vercel).
- Configure all server-only secrets in the host environment.
- Configure Supabase Auth redirect URLs for the production domain.
- Add an automated recurring-rule scheduler before enabling automatic recurring postings.
- Configure production Android signing and Play App Signing; the repository's existing debug key is retained for CI test APKs.
- Add automated integration tests and backups before importing real financial history.
