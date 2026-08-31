#!/usr/bin/env bash
# Local validation: lint every Luau file and build the place.
# Requires rojo + selene (see rokit.toml; `rokit install`).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== selene =="
selene src

echo "== rojo build =="
rojo build -o /tmp/the-11-59-check.rbxlx
echo "OK: /tmp/the-11-59-check.rbxlx"
