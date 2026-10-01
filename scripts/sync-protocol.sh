#!/bin/sh
# Copies protocol/ (JSON Schemas, fixtures, validator) from a checkout of the Clomni server repo, which owns it.
# Both SDKs test against these fixtures; never edit them here.
#   scripts/sync-protocol.sh /path/to/clomni
set -eu
src=${1:?path to the Clomni server repo}
here=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$here/protocol"
cp -R "$src/protocol" "$here/protocol"
rm -rf "$here/protocol/node_modules"
echo "$(git -C "$src" rev-parse HEAD) $(git -C "$src" rev-parse --abbrev-ref HEAD)" > "$here/protocol/SOURCE"
