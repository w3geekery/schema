#!/usr/bin/env bash
# update-scratch-db.sh — Set up or rebuild the Supabase scratch DB for schema verification
#
# IMPORTANT: Run from the schema package directory:
#   cd ~/Projects/w3geekery/zerobias-org-forks/schema/package/w3geekery/sme-mart
#   npm run update-db        # or: bash scripts/update-scratch-db.sh
#
# What it does:
#   1. Tears down any existing content-dev container
#   2. Runs @zerobias-org/util-content-dev-schema to create a fresh Supabase PG17
#      container with full platform DDL, hydra schemas, and migrations
#   3. Optionally loads SME Mart schema via dataloader
#
# Usage:
#   ./scripts/update-scratch-db.sh            # Full rebuild + load SME Mart schema
#   ./scripts/update-scratch-db.sh --db-only  # Rebuild DB only (no schema load)
#
# Prerequisites:
#   - Docker Desktop running
#   - ZB_TOKEN environment variable set
#   - dataloader installed: npm i -g @zerobias-com/platform-dataloader
#
# Database: content_dev on port 15432 (password: welcome)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTAINER_NAME="supabase-pg-content-dev"
DB_PORT=15432
DB_NAME=content_dev
DB_USER=postgres
DB_PASS=welcome
DB_ONLY=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --db-only) DB_ONLY=true ;;
    -h|--help)
      head -22 "$0" | tail -20
      exit 0
      ;;
  esac
done

log()  { printf "\033[1;34m[update]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[  ok  ]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[ warn ]\033[0m %s\n" "$1"; }
fail() { printf "\033[1;31m[ FAIL ]\033[0m %s\n" "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Step 0: Check prerequisites
# ---------------------------------------------------------------------------
log "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  fail "Docker not found."
fi
if ! docker info &>/dev/null 2>&1; then
  fail "Docker daemon not running."
fi
if ! command -v dataloader &>/dev/null; then
  fail "dataloader not found. Install: npm i -g @zerobias-com/platform-dataloader"
fi
if [ -z "${ZB_TOKEN:-}" ]; then
  fail "ZB_TOKEN not set. Required for @zerobias-org registry access."
fi

ok "Prerequisites OK"

# ---------------------------------------------------------------------------
# Step 1: Remove existing container (force fresh start)
# ---------------------------------------------------------------------------
EXISTING=$(docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  log "Removing existing container '$CONTAINER_NAME'..."
  docker stop "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  ok "Old container removed"
fi

if lsof -i ":$DB_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
  fail "Port $DB_PORT is in use."
fi

# ---------------------------------------------------------------------------
# Step 2: Create fresh Supabase scratch DB
# ---------------------------------------------------------------------------
log "Setting up Supabase scratch DB via @zerobias-org/util-content-dev-schema..."
log "(Creates PG17 container with full platform DDL, hydra, migrations, and content)"
# Run setup.sh from its package directory (npx has a path resolution bug
# where it resolves resources relative to bin/ instead of the package dir)
CONTENT_DEV_PKG=$(node -e "try{console.log(require.resolve('@zerobias-org/util-content-dev-schema/setup.sh').replace('/setup.sh',''))}catch{}" 2>/dev/null)
if [ -z "$CONTENT_DEV_PKG" ]; then
  CONTENT_DEV_PKG="$(npm prefix -g)/lib/node_modules/@zerobias-org/util-content-dev-schema"
fi
if [ ! -f "$CONTENT_DEV_PKG/setup.sh" ]; then
  fail "content-dev-schema not found. Install: npm i -g @zerobias-org/util-content-dev-schema@latest"
fi
(cd "$CONTENT_DEV_PKG" && bash setup.sh) 2>&1 || {
  fail "content-dev-schema setup failed"
}
ok "Supabase scratch DB ready on port $DB_PORT"

# ---------------------------------------------------------------------------
# Step 3: Verify connection
# ---------------------------------------------------------------------------
export PGHOST=localhost
export PGPORT=$DB_PORT
export PGUSER=$DB_USER
export PGPASSWORD=$DB_PASS
export PGDATABASE=$DB_NAME
export PGSSLMODE=disable
export PATH="/opt/homebrew/opt/libpq/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

log "Verifying database connection..."
if ! psql -c "SELECT 1;" &>/dev/null 2>&1; then
  fail "Cannot connect to $DB_NAME on port $DB_PORT"
fi
ok "Database connection verified"

if $DB_ONLY; then
  ok "DB-only mode — skipping schema load. Done."
  echo ""
  echo "Connection: postgres://$DB_USER:$DB_PASS@localhost:$DB_PORT/$DB_NAME"
  echo "Next: run 'npm run verify' to test your schema"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Load SME Mart schema
# ---------------------------------------------------------------------------
log "Loading SME Mart schema via dataloader..."
cd "$PKG_DIR"

DATALOADER_OUTPUT=$(dataloader --content-dev --skip-pgboss --skip-dynamo -d "$PKG_DIR" 2>&1) || {
  echo "$DATALOADER_OUTPUT"
  fail "Dataloader failed — see output above"
}

echo "$DATALOADER_OUTPUT"

if echo "$DATALOADER_OUTPUT" | grep -qi '\[error\]'; then
  fail "Dataloader completed with errors — see output above"
fi

ok "SME Mart schema loaded successfully"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
ok "Scratch DB setup complete"
echo ""
echo "Connection: postgres://$DB_USER:$DB_PASS@localhost:$DB_PORT/$DB_NAME"
echo "Container:  docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
echo ""
echo "Next: run 'npm run verify' to test schema changes against this baseline"
