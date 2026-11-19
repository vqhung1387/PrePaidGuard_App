#!/bin/sh
set -eu

if [ -z "${AUTH_DOMAIN:-}" ] && [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
    export AUTH_DOMAIN="$RENDER_EXTERNAL_HOSTNAME"
fi
if [ -z "${AUTH_URI:-}" ] && [ -n "${RENDER_EXTERNAL_URL:-}" ]; then
    export AUTH_URI="$RENDER_EXTERNAL_URL"
fi

alembic upgrade head
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
