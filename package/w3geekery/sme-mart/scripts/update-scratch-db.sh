#!/usr/bin/env bash
# update-scratch-db.sh — Build or update the scratch DB SQL dump for schema verification
#
# IMPORTANT: Run from the schema package directory:
#   cd ~/Projects/w3geekery/zerobias-org-forks/schema/package/w3geekery/sme-mart
#   bash scripts/update-scratch-db.sh
#
# What it does:
#   1. Optionally updates platform-dataloader to latest version
#   2. Starts a fresh PostgreSQL container (sarumont/postgres-plus:latest)
#   3. Creates the scratch database with all DDL, hydra schemas, and migrations
#   4. Loads coretype + base schema content via dataloader
#   5. Saves a SQL dump to .scratch-db/scratch-platform-content-loaded.sql
#   6. Loads SME Mart schema and saves a second dump
#
# The platform-content-loaded dump is what verify-schema.sh restores before
# running the SME Mart dataloader. This means verify tests your schema changes
# against the same baseline the real platform uses.
#
# When to run:
#   - First time setup (no .scratch-db/ directory yet)
#   - After platform-dataloader is updated (new DDL migrations)
#   - After base schema changes
#   - Periodically to stay current with platform DDL
#
# Prerequisites:
#   - Docker Desktop running (with Rosetta enabled for Apple Silicon)
#   - dataloader installed: npm i -g @zerobias-com/platform-dataloader
#   - sem-apply (Ruby gem): gem install schema-evolution-manager
#   - libpq (macOS): brew install libpq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_ROOT="$(cd "$PKG_DIR/../../.." && pwd)"
CONTAINER_NAME="zb-scratch-db"
DB_PORT=5432
DUMP_DIR="$PKG_DIR/.scratch-db"
SKIP_UPDATE=false

# Detect paths
DL_ROOT="$(npm root -g)/@zerobias-com/platform-dataloader"
DL_MODULES="$DL_ROOT/node_modules"
PLATFORM_SQL="$DL_MODULES/@zerobias-com/platform-sql/src/ddl"
CORETYPE_DIR="$DL_MODULES/@zerobias-com/platform-content/src/coretype"
BASE_SCHEMA="$SCHEMA_ROOT/node_modules/@zerobias-org/schema-zerobias-zerobias-base"
SEM_APPLY="$(command -v sem-apply 2>/dev/null || echo "$HOME/.gem/ruby/2.6.0/bin/sem-apply")"

# Parse flags
for arg in "$@"; do
  case $arg in
    --skip-update) SKIP_UPDATE=true ;;
    -h|--help)
      head -32 "$0" | tail -30
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
if [ ! -f "$SEM_APPLY" ]; then
  fail "sem-apply not found at $SEM_APPLY. Install: gem install schema-evolution-manager"
fi
if [ ! -d "$PLATFORM_SQL" ]; then
  fail "platform-sql not found at $PLATFORM_SQL — reinstall dataloader"
fi

ok "Prerequisites OK"

# ---------------------------------------------------------------------------
# Step 1: Optionally update platform-dataloader
# ---------------------------------------------------------------------------
if ! $SKIP_UPDATE; then
  log "Checking for platform-dataloader updates..."
  CURRENT_VER=$(dataloader --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
  LATEST_VER=$(npm view @zerobias-com/platform-dataloader version --registry https://npm.pkg.github.com 2>/dev/null || echo "unknown")
  if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
    ok "platform-dataloader is current ($CURRENT_VER)"
  else
    log "Updating platform-dataloader: $CURRENT_VER -> $LATEST_VER"
    npm i -g @zerobias-com/platform-dataloader@latest 2>&1 || warn "Update failed — continuing with $CURRENT_VER"
    # Re-detect paths after update
    DL_ROOT="$(npm root -g)/@zerobias-com/platform-dataloader"
    DL_MODULES="$DL_ROOT/node_modules"
    PLATFORM_SQL="$DL_MODULES/@zerobias-com/platform-sql/src/ddl"
    CORETYPE_DIR="$DL_MODULES/@zerobias-com/platform-content/src/coretype"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Start fresh container
# ---------------------------------------------------------------------------
EXISTING=$(docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  log "Removing existing container '$CONTAINER_NAME'..."
  docker stop "$CONTAINER_NAME" &>/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" &>/dev/null 2>&1 || true
fi

if lsof -i ":$DB_PORT" -sTCP:LISTEN &>/dev/null 2>&1; then
  fail "Port $DB_PORT is in use."
fi

log "Starting fresh PostgreSQL container..."
docker run -d --name "$CONTAINER_NAME" -p "$DB_PORT:5432" \
  -e POSTGRES_PASSWORD=postgres \
  sarumont/postgres-plus:latest >/dev/null

log "Waiting for PostgreSQL..."
RETRIES=30
until docker exec "$CONTAINER_NAME" pg_isready -U postgres &>/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ $RETRIES -le 0 ]; then fail "PostgreSQL did not start"; fi
  sleep 1
done
ok "PostgreSQL is ready"

# ---------------------------------------------------------------------------
# Step 3: Create scratch database + initial DDL
# ---------------------------------------------------------------------------
DB_URL="postgres://postgres:postgres@localhost:$DB_PORT/scratch?sslmode=disable"
PSQL="docker exec $CONTAINER_NAME psql -U postgres -d scratch"

log "Creating scratch database..."
docker exec "$CONTAINER_NAME" psql -U postgres -c "CREATE DATABASE scratch;" >/dev/null

log "Applying full_schema.sql (first pass — creates catalog tables)..."
docker cp "$PLATFORM_SQL/full_schema.sql" "$CONTAINER_NAME:/tmp/full_schema.sql"
docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -q -f /tmp/full_schema.sql 2>&1 | grep -c "ERROR" || true

# ---------------------------------------------------------------------------
# Step 4: Apply hydra schemas (5 packages in order)
# ---------------------------------------------------------------------------
HYDRA_PACKAGES=(
  "hydra-schema-principal"
  "hydra-schema-resource"
  "hydra-schema-principal-role"
  "hydra-schema-security"
  "hydra-schema-health-check"
)

for pkg in "${HYDRA_PACKAGES[@]}"; do
  PKG_DDL="$DL_MODULES/@zerobias-com/$pkg/src/ddl"
  if [ ! -d "$PKG_DDL" ]; then
    fail "Hydra package DDL not found: $PKG_DDL"
  fi
  log "Applying hydra: $pkg..."
  export PATH="$(dirname "$SEM_APPLY"):/opt/homebrew/opt/libpq/bin:$PATH"
  export GEM_PATH="$HOME/.gem/ruby/2.6.0:${GEM_PATH:-}"
  (cd "$PKG_DDL" && "$SEM_APPLY" --url "$DB_URL" 2>&1) | tail -1
done
ok "All hydra schemas applied"

# ---------------------------------------------------------------------------
# Step 5: Re-apply full_schema.sql (creates 31 catalog views that depend on hydra)
# ---------------------------------------------------------------------------
log "Re-applying full_schema.sql (second pass — creates catalog views)..."
VIEW_COUNT=$(docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -q -f /tmp/full_schema.sql 2>&1 | grep -c "ERROR" || true)
VIEWS=$(docker exec "$CONTAINER_NAME" psql -U postgres -d scratch -tAc \
  "SELECT count(*) FROM information_schema.views WHERE table_schema='catalog' AND table_name LIKE 'vw_%';")
ok "Catalog views created: $VIEWS"

# ---------------------------------------------------------------------------
# Step 6: Apply platform DDL migrations (sem-apply)
# ---------------------------------------------------------------------------
log "Applying platform DDL migrations..."
(cd "$PLATFORM_SQL" && "$SEM_APPLY" --url "$DB_URL" 2>&1) | tail -1
MIGRATION_COUNT=$($PSQL -tAc "SELECT count(*) FROM schema_evolution_manager.scripts;")
ok "Platform migrations applied: $MIGRATION_COUNT"

# ---------------------------------------------------------------------------
# Step 7: Create nil-UUID role
# ---------------------------------------------------------------------------
NIL_ROLE="00000000-0000-0000-0000-000000000000"
$PSQL -c "CREATE ROLE \"$NIL_ROLE\" SUPERUSER LOGIN;" >/dev/null 2>&1 || true
ok "Nil-UUID role ready"

# ---------------------------------------------------------------------------
# Step 8: Load coretype + base schema content
# ---------------------------------------------------------------------------
export PGHOST=localhost PGPORT=$DB_PORT PGUSER=postgres PGPASSWORD=postgres PGDATABASE=scratch PGSSLMODE=disable
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

log "Loading coretype content..."
dataloader --content-dev --skip-pgboss --skip-dynamo -d "$CORETYPE_DIR" 2>&1 | tail -1

log "Loading base schema content..."
dataloader --content-dev --skip-pgboss --skip-dynamo -d "$BASE_SCHEMA" 2>&1 | tail -1

LINK_COUNT=$($PSQL -tAc "SELECT count(*) FROM hydra.link_type;")
ok "Content loaded (hydra.link_type: $LINK_COUNT rows)"

# ---------------------------------------------------------------------------
# Step 9: Save platform-content-loaded dump
# ---------------------------------------------------------------------------
mkdir -p "$DUMP_DIR"

log "Saving platform-content-loaded dump..."
docker exec "$CONTAINER_NAME" pg_dump -U postgres -d scratch --no-owner --no-acl \
  -f /tmp/platform-content-loaded.sql
docker cp "$CONTAINER_NAME:/tmp/platform-content-loaded.sql" \
  "$DUMP_DIR/scratch-platform-content-loaded.sql"
ok "Saved: $DUMP_DIR/scratch-platform-content-loaded.sql"

# ---------------------------------------------------------------------------
# Step 10: Load SME Mart schema + save second dump
# ---------------------------------------------------------------------------
log "Loading SME Mart schema..."
dataloader --content-dev --skip-pgboss --skip-dynamo -d "$PKG_DIR" 2>&1 | tail -1

log "Saving sme-mart-loaded dump..."
docker exec "$CONTAINER_NAME" pg_dump -U postgres -d scratch --no-owner --no-acl \
  -f /tmp/sme-mart-loaded.sql
docker cp "$CONTAINER_NAME:/tmp/sme-mart-loaded.sql" \
  "$DUMP_DIR/scratch-sme-mart-loaded.sql"
ok "Saved: $DUMP_DIR/scratch-sme-mart-loaded.sql"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
log "Cleaning up container..."
docker stop "$CONTAINER_NAME" &>/dev/null
docker rm "$CONTAINER_NAME" &>/dev/null
ok "Container removed"

echo ""
ok "Scratch DB dumps updated successfully"
ls -lh "$DUMP_DIR/"
echo ""
echo "Next: run 'npm run verify' to test your schema against the fresh baseline"
