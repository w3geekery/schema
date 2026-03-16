#!/bin/bash
cd $(dirname $0)
CURRENT=$(pwd)
echo $CURRENT

export NODE_MODULES_DIR=$CURRENT/..
if [ ! -d "$NODE_MODULES_DIR/node_modules" ]; then
  echo "Unable to locate node_modules at $NODE_MODULES_DIR"
  exit 1
fi

CONTENT_PACKAGE="@zerobias-com/platform-content"

PGDATABASE=nfa_catalog_template
dropdb --if-exists $PGDATABASE;

echo "Creating DB $PGDATABASE"
echo ""
createdb $PGDATABASE
status=$?
if [ $status -ne 0 ]; then
  echo "failed creating DB $PGDATABASE"
  exit 1
fi;

psql -d $SU_DB -c 'CREATE ROLE "00000000-0000-0000-0000-000000000000"' || echo "NilUUID role already exists"

TMPDIR=$(mktemp -d)
cd $TMPDIR
npm pack $CONTENT_PACKAGE@1.0.70 --loglevel=error --silent
tar xf zerobias-com-platform-content*.tgz

echo "### Applying schema ${CONTENT_PACKAGE} to database ${PGDATABASE}"
PGOPTIONS='--client-min-messages=warning'
echo "### Dropping DB if exists: $PGDATABASE"
${NODE_MODULES_DIR}/node_modules/@zerobias-org/devops-tools/scripts/db/drop.sh

echo "### (Re-)Creating DB $PGDATABASE"
${NODE_MODULES_DIR}/node_modules/@zerobias-org/devops-tools/scripts/db/create.sh

echo "### Loading ${CONTENT_PACKAGE}"
psql < package/dist/content-full.sql > /dev/null
psql < package/dist/content-data.sql > /dev/null

echo "### Installing Latest Platform GraphqlServer"
npm i -g @zerobias-com/platform-graphql@latest --force --loglevel=error
npm view @zerobias-com/platform-graphql

echo "### Installing Latest TS Generator"
npm i -g @zerobias-com/platform-schema-ts-generator@latest --force --loglevel=error
npm view @zerobias-com/platform-schema-ts-generator

echo "### Installing Latest Dataloader"
npm i -g @zerobias-com/platform-dataloader@latest --force --loglevel=error
npm view @zerobias-com/platform-dataloader
