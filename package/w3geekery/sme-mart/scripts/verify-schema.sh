#!/usr/bin/env bash
# verify-schema.sh — Validate SME Mart schema YAML and run dataloader against Supabase scratch DB
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
#   - Docker Desktop running
#   - ZB_TOKEN environment variable set (for @zerobias-org registry)
#   - dataloader installed: npm i -g @zerobias-com/platform-dataloader
#
# How it works:
#   1. Validates YAML schema files
#   2. Checks enum casing (ALL_CAPS required)
#   3. Starts Supabase PG17 via @zerobias-org/util-content-dev-schema
#      (full platform DDL, hydra schemas, migrations — all automated)
#   4. Runs dataloader with your schema package on top
#   5. Reports success or failure
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
CLEAN_CONTAINER=false
YAML_ONLY=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --clean) CLEAN_CONTAINER=true ;;
    --yaml) YAML_ONLY=true ;;
    -h|--help)
      head -28 "$0" | tail -26
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

# ---------------------------------------------------------------------------
# Step 1b: Enum casing validation (dataloader enforces [A-Z][A-Z0-9_]*)
# ---------------------------------------------------------------------------
log "Checking enum values are ALL_CAPS..."
ENUM_ERRORS=0
for enum_file in "$PKG_DIR"/enums/*.yml; do
  [ -f "$enum_file" ] || continue
  # Extract YAML map keys under 'values:' — enum value names are the keys
  in_values=false
  while IFS= read -r line; do
    if echo "$line" | grep -q '^values:'; then
      in_values=true
      continue
    fi
    if $in_values; then
      # Lines like "  - SOME_VALUE: 'description'" — extract the key
      key=$(echo "$line" | sed -n "s/^[[:space:]]*- \([^:]*\):.*/\1/p")
      if [ -n "$key" ]; then
        if ! echo "$key" | grep -qE '^[A-Z][A-Z0-9_]*$'; then
          warn "Enum value '$key' in $(basename "$enum_file") must be ALL_CAPS (e.g., $(echo "$key" | tr '[:lower:]' '[:upper:]'))"
          ENUM_ERRORS=$((ENUM_ERRORS + 1))
        fi
      fi
    fi
  done < "$enum_file"
done
if [ "$ENUM_ERRORS" -gt 0 ]; then
  fail "Found $ENUM_ERRORS enum values that are not ALL_CAPS — dataloader requires [A-Z][A-Z0-9_]*"
fi
ok "Enum casing check passed"

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

if [ -z "${ZB_TOKEN:-}" ]; then
  fail "ZB_TOKEN not set. Required for @zerobias-org registry access."
fi

# ---------------------------------------------------------------------------
# Step 3: Set up Supabase scratch DB via content-dev-schema
# ---------------------------------------------------------------------------
# Check if the content-dev container is already running with a healthy DB
EXISTING=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  # Container exists and is running — check if DB is ready
  if docker exec "$CONTAINER_NAME" pg_isready -h localhost -p 5432 -U "$DB_USER" &>/dev/null 2>&1; then
    ok "Existing content-dev container found and healthy — reusing"
  else
    log "Existing container not healthy — removing and recreating..."
    docker stop "$CONTAINER_NAME" &>/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" &>/dev/null 2>&1 || true
    EXISTING=""
  fi
fi

if [ -z "$EXISTING" ]; then
  # Also remove stopped containers with this name
  STOPPED=$(docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}" 2>/dev/null || true)
  if [ -n "$STOPPED" ]; then
    docker rm "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  fi

  # Check port availability
  if lsof -i ":$DB_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
    fail "Port $DB_PORT is in use. Stop any service on that port first."
  fi

  log "Setting up Supabase scratch DB via @zerobias-org/util-content-dev-schema..."
  log "(This creates a PG17 container with full platform DDL, hydra, and migrations)"
  # Run setup.sh from its package directory (npx has a path resolution bug
  # where it resolves resources relative to bin/ instead of the package dir)
  CONTENT_DEV_PKG=$(node -e "try{console.log(require.resolve('@zerobias-org/util-content-dev-schema/setup.sh').replace('/setup.sh',''))}catch{}" 2>/dev/null)
  if [ -z "$CONTENT_DEV_PKG" ]; then
    # Fallback: find it in the global npm prefix
    CONTENT_DEV_PKG="$(npm prefix -g)/lib/node_modules/@zerobias-org/util-content-dev-schema"
  fi
  if [ ! -f "$CONTENT_DEV_PKG/setup.sh" ]; then
    fail "content-dev-schema not found. Install: npm i -g @zerobias-org/util-content-dev-schema@latest"
  fi
  (cd "$CONTENT_DEV_PKG" && bash setup.sh) 2>&1 || {
    fail "content-dev-schema setup failed — see output above"
  }
  ok "Supabase scratch DB ready"
fi

# Verify connection
log "Verifying database connection..."
export PGHOST=localhost
export PGPORT=$DB_PORT
export PGUSER=$DB_USER
export PGPASSWORD=$DB_PASS
export PGDATABASE=$DB_NAME
export PGSSLMODE=disable

# Add libpq to PATH (macOS Homebrew)
export PATH="/opt/homebrew/opt/libpq/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if ! psql -c "SELECT 1;" &>/dev/null 2>&1; then
  fail "Cannot connect to content_dev database on port $DB_PORT"
fi
ok "Database connection verified"

# ---------------------------------------------------------------------------
# Step 4: Run dataloader
# ---------------------------------------------------------------------------
log "Running dataloader against content_dev..."
cd "$PKG_DIR"

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
# Step 5: Cleanup
# ---------------------------------------------------------------------------
if $CLEAN_CONTAINER; then
  log "Cleaning up container (--clean)..."
  docker stop "$CONTAINER_NAME" &>/dev/null || true
  docker rm "$CONTAINER_NAME" &>/dev/null || true
  ok "Container removed"
else
  warn "Container '$CONTAINER_NAME' left running on port $DB_PORT. Stop with: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
fi

echo ""
ok "Schema verification complete — all checks passed"
