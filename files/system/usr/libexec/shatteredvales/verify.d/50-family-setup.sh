#!/usr/bin/env bash
#
# 50-family-setup.sh
#
# Purpose:
#   Release-gate check for Home Edition: parses the Family Setup app, so a
#   syntax error fails the build instead of leaving a family without the
#   account wizard. ast.parse writes no bytecode into the read-only /usr.
#
# Usage:
#   Run by /usr/libexec/shatteredvales/build/verify-image.sh at build time.
#
# Exit codes:
#   0 when the app parses, 1 otherwise.

set -euo pipefail

python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' \
    /usr/libexec/shatteredvales/family-setup \
    || { echo "Family Setup does not parse"; exit 1; }
