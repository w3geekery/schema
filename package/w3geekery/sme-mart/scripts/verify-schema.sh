#!/usr/bin/env bash
# verify-schema.sh — Validate SME Mart schema YAML and run dataloader against Docker scratch DB
#
# IMPORTANT: Run from the schema package directory:
#   cd ~/Projects/w3geekery/zerobias-org-forks/schema/package/w3geekery/sme-mart
#   npm run verify           # or: bash scripts/verify-schema.sh
#
# Usage:
#   ./scripts/verify-schema.sh          # Full run: validate YAML + dataloader (keeps container)
#   ./scripts/verify-schema.sh --clean  # Remove container after success
#   ./scripts/verify-schema.sh --yaml   # YAML validation only (no Docker/dataloader)
#
# Prerequisites:
#   - Docker Desktop running (with Rosetta enabled for Apple Silicon)
#   - dataloader installed: npm i -g @zerobias-com/platform-dataloader
#   - SQL dump: .scratch-db/scratch-platform-content-loaded.sql
#     (created by scripts/update-scratch-db.sh)
#
# How it works:
#   1. Validates YAML schema files
#   2. Starts a fresh PostgreSQL container (sarumont/postgres-plus:latest)
#   3. Restores the platform-content-loaded SQL dump (DDL + seed data)
#   4. Runs dataloader with your schema package on top
#   5. Reports success or failure
#
# To reset for a clean run: just run again — it removes the old container automatically.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTAINER_NAME="zb-scratch-db"
DB_PORT=5432
CLEAN_CONTAINER=false
YAML_ONLY=false
DUMP_FILE="$PKG_DIR/.scratch-db/scratch-platform-content-loaded.sql"

# Parse flags
for arg in "$@"; do
  case $arg in
    --clean) CLEAN_CONTAINER=true ;;
    --yaml) YAML_ONLY=true ;;
    -h|--help)
      head -26 "$0" | tail -24
      exit 0
      ;;
  esac
done

log()  { printf "\033[1;34m[verify]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[  ok  ]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[ warn ]\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m[ FAIL ]\033[0m %s\n" "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Step 1: YAML validation (fast, no Docker needed)
# ---------------------------------------------------------------------------
log "Running YAML schema validation..."
cd "$PKG_DIR"
if npm run validate 2>&1; then
  ok "YAML validation passed"
else
  fail "YAML validation failed — fix schema errors before running dataloader"
fi

if $YAML_ONLY; then
  ok "YAML-only mode — skipping dataloader. Done."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: Check prerequisites
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  fail "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
fi

if ! docker info &>/dev/null 2>&1; then
  fail "Docker daemon not running. Start Docker Desktop first."
fi

if ! command -v dataloader &>/dev/null; then
  fail "dataloader not found. Install: npm i -g @zerobias-com/platform-dataloader"
fi

if [ ! -f "$DUMP_FILE" ]; then
  fail "SQL dump not found: $DUMP_FILE — run scripts/update-scratch-db.sh first"
fi

# ---------------------------------------------------------------------------
# Step 3: Handle existing container
# ---------------------------------------------------------------------------
EXISTING=$(docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  log "Removing existing container '$CONTAINER_NAME'..."
  docker stop "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  ok "Stale container removed"
fi

# Check port availability
if lsof -i ":$DB_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
  fail "Port $DB_PORT is in use. Stop local PostgreSQL or other services on that port."
fi

# ---------------------------------------------------------------------------
# Step 4: Start fresh container from base image
# ---------------------------------------------------------------------------
log "Starting fresh PostgreSQL container on port $DB_PORT..."
docker run -d --name "$CONTAINER_NAME" -p "$DB_PORT:5432" \
  -e POSTGRES_PASSWORD=postgres \
  sarumont/postgres-plus:latest >/dev/null

# Wait for PostgreSQL to accept connections
log "Waiting for PostgreSQL to be ready..."
RETRIES=30
until docker exec "$CONTAINER_NAME" pg_isready -U postgres &>/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ $RETRIES -le 0 ]; then
    fail "PostgreSQL did not become ready in time"
  fi
  sleep 1
done
ok "PostgreSQL is ready"

# ---------------------------------------------------------------------------
# Step 5: Create scratch database and restore dump
# ---------------------------------------------------------------------------
log "Creating scratch database..."
docker exec "$CONTAINER_NAME" psql -U postgres -c "CREATE DATABASE scratch;" >/dev/null

log "Restoring platform content dump (DDL + seed data)..."
docker cp "$DUMP_FILE" "$CONTAINER_NAME:/tmp/restore.sql"
RESTORE_ERRORS=$(docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -q -f /tmp/restore.sql 2>&1 | grep -ci "^psql.*ERROR" || true)
if [ "$RESTORE_ERRORS" -gt 5 ]; then
  fail "SQL restore had $RESTORE_ERRORS errors — dump may be corrupt. Regenerate with scripts/update-scratch-db.sh"
fi
ok "Dump restored ($RESTORE_ERRORS minor errors — expected for partitioned tables)"

# Ensure the nil-UUID role exists (dataloader does SET ROLE to this)
NIL_ROLE="00000000-0000-0000-0000-000000000000"
if ! docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -tAc "SELECT 1 FROM pg_roles WHERE rolname='$NIL_ROLE'" 2>/dev/null | grep -q 1; then
  log "Creating required dataloader role ($NIL_ROLE)..."
  docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -c "CREATE ROLE \"$NIL_ROLE\" SUPERUSER LOGIN;" >/dev/null
  ok "Dataloader role created"
fi

# ---------------------------------------------------------------------------
# Step 6: Run dataloader
# ---------------------------------------------------------------------------
log "Running dataloader against scratch DB..."
cd "$PKG_DIR"

# dataloader reads DB config from env vars
export PGHOST=localhost
export PGPORT=$DB_PORT
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=scratch
export PGSSLMODE=disable

# Add libpq to PATH (macOS Homebrew)
export PATH="/opt/homebrew/opt/libpq/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DATALOADER_OUTPUT=$(dataloader --content-dev --skip-pgboss --skip-dynamo -d "$PKG_DIR" 2>&1) || {
  echo "$DATALOADER_OUTPUT"
  fail "Dataloader failed — see output above"
}

echo "$DATALOADER_OUTPUT"

# Check for errors in output (dataloader may exit 0 but log errors)
if echo "$DATALOADER_OUTPUT" | grep -qi '\[error\]'; then
  fail "Dataloader completed with errors — see output above"
fi

ok "Dataloader completed successfully"

# ---------------------------------------------------------------------------
# Step 7: Cleanup
# ---------------------------------------------------------------------------
if $CLEAN_CONTAINER; then
  log "Cleaning up container (--clean)..."
  docker stop "$CONTAINER_NAME" &>/dev/null
  docker rm "$CONTAINER_NAME" &>/dev/null
  ok "Container removed"
else
  warn "Container '$CONTAINER_NAME' left running. Stop with: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
fi

echo ""
ok "Schema verification complete — all checks passed"
