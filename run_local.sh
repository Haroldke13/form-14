#!/usr/bin/env bash
# Run the Form 13 app on this laptop against the local Postgres cluster.
#
# .env keeps the Docker values (host.docker.internal:5432) for container runs.
# python-dotenv never overrides variables already present in the shell, so the
# exports below win for a plain `flask run` on the host. The pbora role and
# database live on the user-owned cluster served by flask-postgres.service
# (127.0.0.1:5433), which needs no sudo to administer.
#
# Usage:
#   ./run_local.sh            # serves on http://127.0.0.1:5566
#   PORT=5000 ./run_local.sh  # pick another port
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

LOCAL_DB_URL="${LOCAL_DB_URL:-postgresql+psycopg2://pbora:pbora@127.0.0.1:5433/pbora}"
export INTERNAL_DATABASE_URL="$LOCAL_DB_URL"
export DATABASE_URL="$LOCAL_DB_URL"
export PBORA_DATABASE_URL="$LOCAL_DB_URL"
export DB_HOST=127.0.0.1
export DB_PORT=5433
export DB_SSL_MODE=disable
export FLASK_APP="${FLASK_APP:-app.py}"
export ADMIN_USER_EMAIL="${ADMIN_USER_EMAIL:-superadmin@example.com}"
export ADMIN_USER_PASSWORD="${ADMIN_USER_PASSWORD:-field.12345}"

PORT="${PORT:-5566}"
echo "Starting Form 13 on http://127.0.0.1:${PORT} using ${LOCAL_DB_URL//pbora:pbora@/pbora:***@}"
exec flask run --host 127.0.0.1 --port "$PORT" "$@"
