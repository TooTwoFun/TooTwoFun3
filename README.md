# TooTwoFun

A short-video community with an in-platform rewards wallet.

## Current status
The GitHub Pages site is currently a front-end prototype. This repository includes the first Supabase database foundation. Login, live uploads, reward verification, moderation, and withdrawals are not live yet.

## Architecture
- Frontend: existing mobile-first HTML/CSS/JS site.
- Backend: Supabase Auth, Postgres and Storage.
- Rewards: server-verified actions, immutable reward ledger, daily limits and idempotency.
- Admin: moderation and payout approval dashboard (planned).

## Backend setup
1. Create a Supabase project.
2. Open SQL Editor and run supabase/migrations/001_initial_schema.sql.
3. Create a private Storage bucket named videos. Add safe upload and read policies before enabling uploads.
4. Configure the frontend with the Supabase project URL and anon/publishable key. Never put the service_role key in browser code or GitHub.
5. Implement Supabase Edge Functions for upload moderation and reward verification before enabling coin rewards.

## Reward safety
- Rewards apply only to actions inside TooTwoFun, not external social likes or shares.
- Watch rewards require server-side watch-session checks, visibility checks, minimum watch time and replay limits.
- Upload rewards require moderation and quality checks.
- Like/comment/share rewards need per-user, per-video and daily limits plus spam/fraud detection.
- Never let the browser write to wallets or reward_ledger.
- Reward amounts remain disabled at zero until a sustainable revenue source funds them.
- Withdrawals require risk review and admin approval. Publish minimum thresholds, fees and payout terms before launch.

GitHub Pages serves static files only. Supabase is required for authentication, database, storage and secure reward processing.
