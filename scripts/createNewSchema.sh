#! /bin/sh

if [ $# -ne 1 ]; then
    echo "Usage: $0 <folder_path>"
    exit 1
fi

FOLDER_PATH=$1;
FOLDER_NAME=$(basename $FOLDER_PATH);
BASE_DIR=$(dirname $0);

if [ ! -d "$FOLDER_PATH" ]; then
  echo "Folder $FOLDER_PATH does not exist."
  exit 1
fi

cp -r $BASE_DIR/../templates/* $BASE_DIR/../$FOLDER_PATH
cp  $BASE_DIR/../.npmrc $BASE_DIR/../$FOLDER_PATH

sed -i "s/{code}/$FOLDER_NAME/g" $BASE_DIR/../$FOLDER_PATH/package.json

UUID=$(uuidgen)
sed -i "s/{id}/$UUID/g" $BASE_DIR/../$FOLDER_PATH/catalog.yml
sed -i "s/{code}/$FOLDER_NAME/g" $BASE_DIR/../$FOLDER_PATH/catalog.yml
