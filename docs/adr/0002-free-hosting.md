# ADR 0002: Render free web service with a Supabase free Postgres

- Status: accepted
- Date: 2026-09-19

## Context

The public demo must cost nothing, stay reachable for anyone who opens the README link, and keep a real database with demo data that is reset every night. The app is one Docker image (Rails with Solid Queue inside Puma, the SPA built into `public/`) that needs about 350 to 512 MB of memory and one Postgres database, because Solid Queue and Solid Cache share it (see the jobs migration). Prices and limits below were read from the providers' pages on 2026-09-19.

Constraints found:
- Render's free Postgres is deleted 30 days after creation.
- Neon's free tier suspends compute after 5 idle minutes and caps compute at 100 hours a month; Solid Queue polls the database every second while the app is up, so the cap would run out around day 16.
- Supabase's free Postgres (500 MB) has no compute cap, pauses only after 7 days of low activity, and offers an IPv4 session pooler that keeps prepared statements working.
- Koyeb, Fly.io and Railway no longer offer a usable free tier to new accounts. Oracle Always Free is a full VM but needs a credit card, has no managed TLS or subdomain, and reclaims idle instances.
- Render's free web service has 512 MB, sleeps after 15 minutes without traffic (about a minute to wake), gives 750 instance hours a month and blocks outbound SMTP ports.

## Options

| | Render web + Supabase | Render web + Neon | Oracle Always Free VM |
|---|---|---|---|
| Cost | zero, no card | zero, no card | zero, card required |
| Database lifetime | no expiry | no expiry | self-managed |
| Always on | with a keep-alive ping | no: cold starts, compute cap | yes |
| Operations | managed TLS and subdomain | managed | TLS, backups and upgrades by hand |
| Backups | none on free; dumps from CI | 6 hour restore window | by hand |

## Decision

Render free web service (region Virginia) running the Docker image, and a Supabase free Postgres in `us-east-1` through the session pooler, configured by `render.yaml`:

- One Puma process (`WEB_CONCURRENCY=0`, 3 threads) with Solid Queue inside it (`SOLID_QUEUE_IN_PUMA`, one job thread) to stay under 512 MB.
- `APP_HOST` falls back to `RENDER_EXTERNAL_HOSTNAME`, so the host allow list works without a manual value.
- Render deploys only after the commit's CI checks pass.
- An external uptime monitor requests `/up` every 5 minutes. That keeps the demo awake (one service fits in 750 hours), lets the nightly reset run as a Solid Queue recurring task, and keeps Supabase active. Render may still restart a free instance at any time; the demo tolerates that.
- Email goes through Brevo's HTTPS API, since SMTP ports are blocked and Brevo sends to any recipient without an owned domain. Uploads, if any, are stored in Postgres.
- Backups: a scheduled GitHub Actions workflow dumps the database and restores the dump into a throwaway Postgres in the same run; that is the documented restore test.

## Consequences

- The demo answers fast while the monitor runs; if the monitor stops, the first request after a pause waits about a minute and the nightly reset may be skipped.
- The app talks to a database in the same AWS region, and users in Brazil see roughly 120 to 150 ms of latency.
- There is no managed backup, so the CI dump is the only one. Scheduled workflows in public repositories stop after 60 days without activity.
- Demo emails come from a Brevo relay address and may land in spam; the demo also shows invitation links on screen.
- Two providers hold the demo's secrets (`DATABASE_URL` on Render, the database password on Supabase); rotation is described in `docs/deploy.md`.

## What would make me change my mind

- The demo needing more than 512 MB after the reports slice: move to a paid instance or the Oracle VM.
- Supabase pausing the project despite the traffic, or changing the free tier: move the database to Neon and accept cold starts.
- Render prohibiting keep-alive pings or changing the free tier.
