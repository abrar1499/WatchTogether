# Pocket AI — AI-first Expense Manager

This repository is being transformed from the original WatchTogether Android project into **Pocket AI**, a chat-first personal finance manager.

## Applications
- **Web:** Next.js 15 + TypeScript + Tailwind in [web/](web/). Includes a responsive dashboard, conversational command input, CSV export, light/dark themes, Supabase authentication, server-side AI provider settings, and an installable PWA.
- **Android:** a native Kotlin WebView companion in the existing Android project. It opens the deployed Pocket AI web app using the `WEB_APP_URL` build setting. The PWA can also be installed directly from Chrome on Android.

## Quick start
Read [web/README.md](web/README.md) for local development, Supabase schema setup, AI key security, and Android build configuration.

## Required backend setup
The repository does not contain your Supabase project credentials or provider API keys. Configure these as environment secrets on your deployment host:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server only)
- `CREDENTIALS_ENCRYPTION_KEY` (server only; 32 bytes)
- `WEB_APP_URL` (GitHub Actions secret for the Android WebView build)

Run the SQL migration at `web/supabase/migrations/0001_initial_schema.sql` in your Supabase project.

## Demo mode
A private, local-only demo is available without Supabase. It is intended for exploration only; demo records are not cloud-backed and must not be treated as real financial records.
