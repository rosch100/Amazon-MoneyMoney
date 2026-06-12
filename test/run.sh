#!/bin/bash -e
# Run a Lua test script under luajit with the luarocks 5.1 module paths set up.
# Usage: test/run.sh test/selftest.lua   (or any harness script)
export PATH="/opt/homebrew/bin:$PATH"
eval "$(luarocks --lua-version=5.1 path)"
cd "$(dirname "$0")/.."
exec luajit "${1:-test/selftest.lua}" "${@:2}"
