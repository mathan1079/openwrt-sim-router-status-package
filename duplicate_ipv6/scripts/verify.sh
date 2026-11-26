#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for script in scripts/*.sh; do sh -n "$script"; done
python3 -m unittest discover -s tests -p 'test_*.py' -v
