#! /usr/bin/bash

URL=${1:-https://download.opensuse.org/tumbleweed/repo/oss}

mkdir -p repodata

# download the main index with its GPG signatures
FILE="repodata/repomd.xml"
echo "Downloading $URL/$FILE..."
curl -s -L -o "$FILE" "$URL/$FILE"

FILE="repodata/repomd.xml.asc"
echo "Downloading $URL/$FILE..."
curl -s -L -o "$FILE" "$URL/$FILE"

FILE="repodata/repomd.xml.key"
echo "Downloading $URL/$FILE..."
curl -s -L -o "$FILE" "$URL/$FILE"

# download the referenced files from the index
grep href repodata/repomd.xml | sed -e 's/^\s*<location href="//' -e 's#"/>$##' \
 | xargs -I % bash -c "echo \"Downloading $URL/%...\" && curl -s -L -o % \"$URL/%\""
