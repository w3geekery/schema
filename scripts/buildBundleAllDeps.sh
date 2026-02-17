#!/bin/bash
set +x
PACKAGE_NAMES=$(npx lerna exec -- 'yq e .name package.json')
PACKAGE_ARR=($PACKAGE_NAMES)
PACKAGE_VERSIONS=$(npx lerna exec -- 'yq e .version package.json')
PACKAGE_VERSION_ARR=($PACKAGE_VERSIONS)
DEPS="\"dependencies\": {\n"
LENGTH=${#PACKAGE_ARR[@]};
echo $LENGTH
for ((i=0;i < $LENGTH; i++)); do
  PACKAGE_NAME=${PACKAGE_ARR[$i]}
  PACKAGE_VERSION=${PACKAGE_VERSION_ARR[$i]}
  echo "Working with schema $PACKAGE_NAME -- $PACKAGE_VERSION"
  DEPS="$DEPS\"$PACKAGE_NAME\": \"^$PACKAGE_VERSION\"\n"
done

DEPS="$DEPS}"
echo -e $DEPS;
