# skale-cron — a minimal container that runs supercronic against a single
# versioned crontab covering scheduled jobs for every project in the
# Skale-Club org. Replaces per-project GitHub Actions cron workflows (see
# README.md for the billing rationale).

FROM alpine:3.20

# supercronic release pin. Do NOT bump to "latest" — always look up the
# current stable release, grab its published SHA1SUMS entry for
# supercronic-linux-amd64, and update both ARGs together.
# https://github.com/aptible/supercronic/releases/tag/v0.2.49
ARG SUPERCRONIC_VERSION=v0.2.49
ARG SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64
ARG SUPERCRONIC_SHA1SUM=e63c11a9726b775a6a11801e81af4f3fb926aa68
ARG SUPERCRONIC=supercronic-linux-amd64

RUN apk add --no-cache curl bash ca-certificates tzdata \
 && curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" /usr/local/bin/supercronic \
 && addgroup -S cron && adduser -S -G cron cron

WORKDIR /app

COPY tick.sh /app/tick.sh
COPY crontab /app/crontab
RUN chmod +x /app/tick.sh \
 && chown -R cron:cron /app

USER cron

# TZ defaults to UTC in .env.example so crontab entries below keep the exact
# same wall-clock semantics as the GitHub Actions `cron:` expressions they
# replace. Override TZ only if you intentionally want local-time schedules.
ENV TZ=UTC

CMD ["supercronic", "/app/crontab"]
