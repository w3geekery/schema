#!/bin/sh
cd $(dirname $0)

if [ "$#" -ne 1 ] ; then
  echo "Usage: generate.sh <package_path>" >&2
  exit 1
fi

PACKAGE_JSON="$1/package.json"
if [ ! -f "$PACKAGE_JSON" ]; then
  echo "Unable to locate $PACKAGE_JSON"
  exit 1
fi

PACKAGE_NAME=$(jq -r '(.zerobias // .auditmation).package' $PACKAGE_JSON)
ARTIFACT_NAME=$(jq -r '.name' $PACKAGE_JSON)
VERSION=$(jq -r '.version' $PACKAGE_JSON)
REPO_DIR=$(jq -r '.repository.directory' $PACKAGE_JSON)

echo "Generating code for artifact=$ARTIFACT_NAME@$VERSION and package=$PACKAGE_NAME"
jq --arg artifact "$ARTIFACT_NAME" --arg version "$VERSION" --arg repodir "$REPO_DIR" \
  '.name |= sub("\\{ARTIFACT_NAME\\}"; $artifact) | .description |= sub("\\{ARTIFACT_NAME\\}"; $artifact) | .version |= sub("\\{VERSION\\}"; $version) | .repository.directory |= sub("\\{REPO_DIR\\}"; $repodir)' \
  package-template.json > package.json
status=$?
if [ $status -ne 0 ]; then
  echo "Unable to generate package from template"
  exit 1
fi

echo "Installing dependencies..."
npm install --workspaces=false --install-strategy=nested
status=$?
if [ $status -ne 0 ]; then
  echo "Failed installing dependencies"
  exit 1
fi

echo "Generating code in src/"
npm run generate -- -p $PACKAGE_NAME -o ./src
status=$?
if [ $status -ne 0 ]; then
  echo "Failed generating typescript"
  exit 1
fi

echo "Transpiling generated code"
npm run transpile
status=$?
if [ $status -ne 0 ]; then
  echo "Failed transpiling generated code"
  exit 1
fi

exit 0
