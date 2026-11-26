#!/usr/bin/env bash
# Exit 0 when the current directory is a Nuxt project.
set -euo pipefail

for f in nuxt.config.ts nuxt.config.js nuxt.config.mjs; do
  [ -f "$f" ] && exit 0
done
[ -f package.json ] && grep -qE '"nuxt"\s*:' package.json && exit 0
exit 1
