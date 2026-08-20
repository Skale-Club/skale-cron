#!/bin/bash
# tick.sh — cron job wrapper used by every line in crontab.
#
# Fires one authenticated HTTP request, logs a single structured line to
# stdout (supercronic captures it), reports a heartbeat to Xphere, and
# alerts on Telegram when the job fails. Deliberately does NOT use `set -e`:
# a failing job must not kill the runner or block the rest of the crontab —
# supercronic keeps the container alive for every other job regardless of
# what any one tick does.
#
# Usage: tick.sh <project> <job_name> <url> [expected_interval_seconds] [max_seconds]
#
#   <project>  Short uppercase slug identifying which app this job belongs
#              to: XPHERE, XKEDULE, SKALECLUB, XTIMATOR, ... Drives which
#              secret and which Telegram bot get used (see below) — every
#              app has its own bot, there is no single shared bot token.
#
# Env read:
#   <PROJECT>_CRON_SECRET
#              Bearer token sent to <url>. Resolved from the project arg,
#              e.g. project=XKEDULE reads $XKEDULE_CRON_SECRET.
#   CRON_SECRET_OVERRIDE
#              If set, used instead of <PROJECT>_CRON_SECRET for this one
#              call. Exists for the xphere scrape-reviews job, which
#              authenticates with OPERATOR_AUTOMATION_SECRET instead of its
#              project's normal cron secret — an xphere-specific exception,
#              not the general case.
#   HTTP_METHOD
#              HTTP method for the job request. Default GET. Override per
#              crontab line for POST endpoints.
#   XPHERE_BASE_URL, XPHERE_CRON_SECRET
#              The heartbeat endpoint (…/api/cron/heartbeat) lives on the
#              Xphere platform regardless of which project's job ran, so
#              the heartbeat POST always targets XPHERE_BASE_URL and always
#              authenticates with XPHERE_CRON_SECRET — never the per-project
#              secret above.
#   TELEGRAM_BOT_TOKEN_<PROJECT>, TELEGRAM_ALERT_CHAT_ID_<PROJECT>
#              Per-project Telegram bot used for failure alerts. Resolution
#              order:
#                1. TELEGRAM_BOT_TOKEN_<PROJECT> / TELEGRAM_ALERT_CHAT_ID_<PROJECT>
#                2. TELEGRAM_BOT_TOKEN_OPS / TELEGRAM_ALERT_CHAT_ID_OPS
#                   (shared ops bot — fallback for a project with no bot
#                   of its own yet)
#                3. neither set -> alert is skipped silently (Telegram is
#                   never a startup requirement; heartbeats still fire and
#                   failures are still visible in stdout logs either way).
#
# Exit code is always 0.

set -uo pipefail

project="${1:?tick.sh: project required (e.g. XPHERE)}"
job_name="${2:?tick.sh: job_name required}"
url="${3:?tick.sh: url required}"
expected_interval_seconds="${4:-0}"
max_seconds="${5:-120}"
http_method="${HTTP_METHOD:-GET}"
project_upper="${project^^}"

body_file="/tmp/body.$$"
err_file="/tmp/curl_err.$$"
cleanup() { rm -f "$body_file" "$err_file"; }
trap cleanup EXIT

# json_escape: minimal JSON string escaper for stdin -> stdout. Handles the
# characters actually likely to show up in a response body/error snippet
# (backslash, double quote, newline). Not a general-purpose JSON encoder —
# good enough for a truncated log/alert string, not for arbitrary payloads.
json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

# --- resolve this job's own auth secret (per project, with override) ---
if [ -n "${CRON_SECRET_OVERRIDE:-}" ]; then
  job_secret="$CRON_SECRET_OVERRIDE"
else
  job_secret_var="${project_upper}_CRON_SECRET"
  job_secret="${!job_secret_var:-}"
fi

# --- fire the job -----------------------------------------------------
# curl reports its own wall-clock time via %{time_total} (seconds, fractional).
# We use that instead of `date +%N` because Alpine's busybox `date` does not
# reliably support sub-second formatting.
curl_out=$(curl -sS -o "$body_file" -w '%{http_code} %{time_total}' \
  --connect-timeout 15 --max-time "$max_seconds" \
  -X "$http_method" \
  -H "Authorization: Bearer ${job_secret}" \
  "$url" 2>"$err_file")
curl_exit=$?

http_status="${curl_out%% *}"
time_total="${curl_out##* }"
curl_err="$(cat "$err_file" 2>/dev/null || true)"

duration_ms=$(awk -v t="${time_total:-0}" 'BEGIN{printf "%d", (t*1000)+0.5}')

# Normalize to 0 on hard connection failure (curl error, empty/000 status)
# per the heartbeat contract: "0 on connection failure".
if [ "$curl_exit" -ne 0 ] || [ -z "$http_status" ] || [ "$http_status" = "000" ]; then
  status=0
else
  status="$http_status"
fi

body="$(cat "$body_file" 2>/dev/null || true)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- structured stdout log line (this is what supercronic captures) ---
echo "timestamp=${timestamp} project=${project_upper} job=${job_name} status=${status} duration_ms=${duration_ms}"

# --- build the error string (max 300 chars) for the heartbeat + alert ---
is_failure=0
error_text=""
if [ "$status" -eq 0 ]; then
  is_failure=1
  error_text="connection failed: ${curl_err:-curl exit ${curl_exit}}"
elif [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
  is_failure=1
  error_text="$body"
fi
error_text="${error_text:0:300}"

# --- heartbeat: always sent, and its own failure must never fail this script ---
# Fixed target regardless of <project> — the heartbeat endpoint is on the
# Xphere platform itself, not on whichever app the job belongs to.
if [ -n "${XPHERE_BASE_URL:-}" ]; then
  if [ -n "$error_text" ]; then
    error_json="$(printf '%s' "$error_text" | json_escape)"
    error_field="\"${error_json}\""
  else
    error_field="null"
  fi

  # cron_heartbeats.job_name is a PRIMARY KEY in a single table shared by every
  # app on the ops hub, so the bare job name is not a safe key: two projects
  # can both want a job called "keepalive" or "cleanup" and would silently
  # overwrite each other's heartbeat. Qualify it with the project slug here —
  # one place, so crontab lines stay readable — which also makes the alert
  # title in obs-alerts name the offending app on its own.
  qualified_job_name="$(printf '%s/%s' "${project_upper,,}" "$job_name")"

  # expected_interval_seconds is optional in the endpoint's schema and must be
  # POSITIVE when present (z.number().int().positive()). tick.sh defaults it to
  # 0 when the arg is omitted (the README's single-job test invocation does
  # exactly that), so send the field only when we actually have a value —
  # otherwise the whole heartbeat is rejected with a 422 that the `|| true`
  # below would swallow, leaving a job that looks silent when it is fine.
  if [ "$expected_interval_seconds" -gt 0 ] 2>/dev/null; then
    interval_field=$(printf '"expected_interval_seconds":%s,' "$expected_interval_seconds")
  else
    interval_field=""
  fi

  heartbeat_payload=$(printf '{"job_name":"%s","status":%s,"duration_ms":%s,%s"error":%s}' \
    "$qualified_job_name" "$status" "$duration_ms" "$interval_field" "$error_field")

  curl -sS -o /dev/null \
    --connect-timeout 10 --max-time 15 \
    -X POST \
    -H "Authorization: Bearer ${XPHERE_CRON_SECRET:-}" \
    -H "Content-Type: application/json" \
    -d "$heartbeat_payload" \
    "${XPHERE_BASE_URL%/}/api/cron/heartbeat" >/dev/null 2>&1 || true
fi

# --- Telegram alert on non-2xx or timeout/connection failure ---
if [ "$is_failure" -eq 1 ]; then
  bot_token_var="TELEGRAM_BOT_TOKEN_${project_upper}"
  chat_id_var="TELEGRAM_ALERT_CHAT_ID_${project_upper}"
  bot_token="${!bot_token_var:-}"
  chat_id="${!chat_id_var:-}"

  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    # No project-specific bot configured yet — fall back to the shared ops bot.
    bot_token="${TELEGRAM_BOT_TOKEN_OPS:-}"
    chat_id="${TELEGRAM_ALERT_CHAT_ID_OPS:-}"
  fi

  if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
    truncated_body="$(printf '%s' "$body" | head -c 500)"
    message=$(printf '*skale-cron alert*\nProject: `%s`\nJob: `%s`\nStatus: %s\nDuration: %sms\nBody: `%s`' \
      "$project_upper" "$job_name" "$status" "$duration_ms" "$truncated_body")

    # Best-effort: Telegram's plain "Markdown" parse mode is picky about
    # unescaped _ * [ ] ` in arbitrary body text. This is an ops alert, not
    # user-facing UI, so we accept occasional formatting glitches rather
    # than hand-rolling a full MarkdownV2 escaper here.
    curl -sS -o /dev/null \
      --connect-timeout 10 --max-time 15 \
      --data-urlencode "chat_id=${chat_id}" \
      --data-urlencode "text=${message}" \
      --data-urlencode "parse_mode=Markdown" \
      "https://api.telegram.org/bot${bot_token}/sendMessage" >/dev/null 2>&1 || true
  else
    # Telegram is never a startup requirement and this must never be fatal —
    # just make the gap visible in container logs instead of failing silently.
    echo "timestamp=${timestamp} project=${project_upper} job=${job_name} alert=skipped reason=no_telegram_bot_configured"
  fi
fi

exit 0
