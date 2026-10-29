#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
revision=2200871d9cef988051d2a99d67df3bda6cbb30a8
expected=e1e2ad6c6fbf568afee5993ef8b2b91ab013d21698c9304e079e633ad82776f5
mkdir -p Downloads Tools
archive=Downloads/exiftool-13.59.tar.gz
if [[ ! -f "$archive" ]]; then
  curl --fail --location "https://codeload.github.com/exiftool/exiftool/tar.gz/$revision" --output "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
if [[ "$actual" != "$expected" ]]; then print -u2 'ExifTool checksum mismatch'; exit 1; fi
if [[ ! -d Tools/ExifTool ]]; then
  mkdir -p Tools/ExifTool
  tar -xzf "$archive" --strip-components=1 -C Tools/ExifTool
fi
/usr/bin/perl Tools/ExifTool/exiftool -config '' -ver
