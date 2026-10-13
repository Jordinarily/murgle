#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

for tool in stylua luac5.1 lua5.1 python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing required validation tool: %s\n' "$tool" >&2
        exit 1
    fi
done

stylua --check .
find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 tests/test_package.py
