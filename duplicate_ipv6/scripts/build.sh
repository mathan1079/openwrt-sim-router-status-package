#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "${FORMAT:-both}" in
 ipk) exec ./scripts/build-ipk.sh;;
 apk) exec python3 scripts/build-apk.py;;
 both) ./scripts/build-ipk.sh; exec python3 scripts/build-apk.py;;
 *) echo 'FORMAT must be ipk, apk, or both' >&2; exit 2;;
esac
