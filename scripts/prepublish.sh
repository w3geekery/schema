#!/bin/bash
### This script is invoked by the nx:prepublish target on each publishable schema.
### It creates a fresh database from the template created by `prepublish-init.sh`,
### loads the schema using dataloader, runs GraphQL SchemaBuilder, then generates
### TypeScript interfaces under a `ts/` directory inside the schema's location.
set -e
set -x

package_path=$(pwd)

cd $(dirname $0)
CURRENT=$(pwd)
echo $CURRENT

if [ ! -f "$package_path/package.json" ]; then
  echo "Unable to locate package.json at $package_path"
  exit 1
fi

packagejson=$package_path/package.json
PGOPTIONS='--client-min-messages=warning'

PGDATABASE=$(jq -r '.["name"]' $packagejson)
echo "Creating DB $PGDATABASE from template"
dropdb --if-exists $PGDATABASE
createdb $PGDATABASE -T nfa_catalog_template

echo "Loading schemas at $package_path"
LOG_LEVEL=warning dataloader -d $package_path --skip-pgboss
status=$?
if [ $status -ne 0 ]; then
  echo "Failed loading artifact $package_path"
  dropdb $PGDATABASE
  exit 1
fi;

echo "Successfully loaded artifact $package_path"
echo "Running GraphQL test-start against $package_path"
npx @zerobias-com/platform-graphql --test-start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed running GraphQL SchemaBuilder for artifact $package_path"
  dropdb $PGDATABASE
  exit 1
fi;

echo "Successfully ran GraphQL SchemaBuilder for artifact $package_path"
deprecated=$(jq -r '(.zerobias // .auditmation).deprecated' $packagejson)

# Do not generate ts when deprecating the artifact
if [ "$deprecated" != "true" ]; then
  TS_DIR=$package_path/ts
  if [ -d "$TS_DIR" ]; then
    echo "Removing local ts directory"
    rm -rf $package_path/ts
  fi

  mkdir $TS_DIR
  echo "Created directory $TS_DIR"

  cp ../libs/utils/ts-schema-package-template/.npmrc $TS_DIR
  cp ../libs/utils/ts-schema-package-template/* $TS_DIR

  sh $TS_DIR/generate.sh $package_path
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed generating typescript for $package_path"
    dropdb $PGDATABASE
    exit 1
  fi;

  echo "Successfully generated typescript for $package_path"
fi;

dropdb $PGDATABASE
