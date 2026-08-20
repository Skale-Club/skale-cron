# skale-cron

A single small container that triggers the scheduled HTTP jobs for every
Skale-Club project, using [supercronic](https://github.com/aptible/supercronic)
against one versioned `crontab`.

## What this replaces, and why

The Skale-Club GitHub org was burning roughly 8,654 GitHub Actions minutes a
month, ~95% of it from cron workflows that do nothing but `curl` an endpoint
for 7-47 seconds — but GitHub bills every scheduled run a full minute
regardless of how long it actually took. The work those endpoints do already
runs on a Hetzner VPS managed by Coolify; only the *trigger* lived on GitHub
Actions. This service moves the trigger onto that same VPS, where firing a
`curl` costs nothing.

Each job here is a one-line mirror of what its GitHub Actions workflow did:
same endpoint, same auth header, same timeout — cadences are intentionally
retuned where the plan allows it (see the comments in `crontab`).

## Deploying on Coolify

Either point Coolify at this repo/directory with the `Dockerfile` build pack,
or build and push to GHCR and deploy from the image:

```bash
docker build -t ghcr.io/<org>/skale-cron:latest .
docker push ghcr.io/<org>/skale-cron:latest
```

Then, as a Coolify service:

1. Create a new resource -> Dockerfile (or "Docker Image" if using GHCR).
2. Set the environment variables from `.env.example` (below) in Coolify's
   environment tab — do not bake secrets into the image.
3. No exposed port is needed; this container only runs outbound `curl`
   calls on a schedule, nothing listens for inbound traffic.
4. Deploy. Check logs for the structured `timestamp=... job=... status=...`
   lines from `tick.sh` to confirm jobs are firing.

## Environment variables

See `.env.example` for the authoritative, commented list. Summary:

| Var | Required | Purpose |
|---|---|---|
| `XPHERE_BASE_URL` | yes | xphere origin used to build every xphere job's URL, and the fixed target for the heartbeat POST regardless of which project's job ran |
| `XPHERE_CRON_SECRET` | yes | bearer token for xphere's `/api/cron/*` routes; also authenticates the heartbeat POST for every job, from any project |
| `OPERATOR_AUTOMATION_SECRET` | yes (for scrape-reviews) | xphere-specific exception — `scrape-reviews` authenticates with this instead of `XPHERE_CRON_SECRET` |
| `TELEGRAM_BOT_TOKEN_XPHERE` / `TELEGRAM_ALERT_CHAT_ID_XPHERE` | no | xphere's own alert bot, once created |
| `TELEGRAM_BOT_TOKEN_OPS` / `TELEGRAM_ALERT_CHAT_ID_OPS` | no | shared fallback bot for any project without its own bot yet |
| `TZ` | no (default `UTC`) | keep at UTC so `crontab` cadences match the GitHub `cron:` expressions they replace |
| `XKEDULE_*`, `SKALECLUB_*`, `XTIMATOR_*` | no, yet | same `BASE_URL` / `CRON_SECRET` / Telegram-bot-pair shape as xphere, for the commented Phase 3/4 jobs |

**Telegram is never required to start or run this service.** Every job runs,
heartbeats still POST to xphere, and failures are still logged to stdout as
structured lines even with zero `TELEGRAM_*` vars set. Per-app bots are being
created as a follow-up to this migration — until then, `tick.sh` resolves
each project's bot with this fallback order:

1. `TELEGRAM_BOT_TOKEN_<PROJECT>` / `TELEGRAM_ALERT_CHAT_ID_<PROJECT>`
2. `TELEGRAM_BOT_TOKEN_OPS` / `TELEGRAM_ALERT_CHAT_ID_OPS`
3. neither set -> alert is skipped silently, with one stdout log line
   noting which project had no bot configured, so the gap is visible in
   container logs instead of invisible.

## Adding a new job

Add one line to `crontab`:

```
*/10 * * * * /app/tick.sh <PROJECT> <job-name> "${<PROJECT>_BASE_URL}/api/cron/<job-name>" <expected_interval_seconds> <max_seconds>
```

- `<PROJECT>` is the uppercase slug (`XPHERE`, `XKEDULE`, ...) — it drives
  which `<PROJECT>_CRON_SECRET` and which Telegram bot `tick.sh` resolves
  automatically. No per-line secret wiring needed unless the job is an
  exception (see `scrape-reviews` in `crontab` for the pattern: prefix the
  line with `CRON_SECRET_OVERRIDE=...` and/or `HTTP_METHOD=POST`).
- `expected_interval_seconds` should match the cron cadence in seconds
  (e.g. `600` for `*/10`) — it's passed through on the heartbeat payload for
  drift/staleness detection on the xphere side.
- `max_seconds` should be a little above the endpoint's real p99 latency,
  not an arbitrary large number — it becomes curl's `--max-time`.
- Add the corresponding `<PROJECT>_BASE_URL` / `<PROJECT>_CRON_SECRET` (and,
  optionally, its Telegram bot pair) to the deployed environment.

## Testing a single job locally

```bash
docker build -t skale-cron .
docker run --rm --env-file .env skale-cron \
  /app/tick.sh XPHERE campaign-tick "https://xphere.app/api/cron/campaign-tick"
```

This runs exactly one tick and exits — it does not start supercronic. Check
the printed `timestamp=... job=... status=... duration_ms=...` line, and
confirm a heartbeat landed against `XPHERE_BASE_URL`'s `/api/cron/heartbeat`.

## Internal networking (bypassing Cloudflare's 100s timeout)

`global-knowledge-notion` legitimately runs 88-103 seconds draining the
Notion sync queue. Routed through Cloudflare's proxy, any origin request
over ~100s gets dropped with a 524 — the original GitHub Actions workflow
worked around this by resolving `xphere.app` straight to the origin IP with
`curl --resolve`.

Since this container runs on the *same* Docker host as the xphere app
(both are Coolify-managed services on the same Hetzner box), there's a
cleaner fix available: once this service and the xphere app container share
a Docker network, `XPHERE_BASE_URL` can point straight at the xphere
container's internal service URL — e.g. `http://<coolify-service-name>:3000`
— instead of `https://xphere.app`. That traffic never touches Cloudflare, so
the 100s proxy limit doesn't apply at all.

**The container/service name must be confirmed in the Coolify dashboard for
the xphere app before switching this** — do not guess it. Once confirmed,
update `XPHERE_BASE_URL` in this service's environment and redeploy; no code
change is needed. Until then, leave `XPHERE_BASE_URL` at
`https://xphere.app` and rely on `global-knowledge-notion`'s generous
`max_seconds` (180) for headroom.
