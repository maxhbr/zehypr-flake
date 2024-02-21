#!/usr/bin/env bash

set -euo pipefail

outfile="$(readlink -f data.json)"

json="$(curl  https://api.github.com/repos/zephyrproject-rtos/sdk-ng/releases |
  jq '.[0]| { tag: .tag_name , url : (.assets[] | select( .name | test("zephyr-sdk-.*_linux-x86_64.tar.xz") ).browser_download_url) }')"

hash="$(nix store prefetch-file --json --hash-type sha512 $(echo "$json" | jq -r .url) | jq -r .hash)"
echo "$json" | jq --arg hash "$hash" '. + {hash: $hash}' | tee "$outfile"

git add data.json
git commit -m "update data.json"
