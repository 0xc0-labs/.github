#!/usr/bin/env bash
# Cases for component-paths.sh, through changes.sh's decision:
# `bash .github/actions/component-paths/test.sh`.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=component-paths.sh
. "$here/component-paths.sh"
# shellcheck source=../changes/changes.sh
. "$here/../changes/changes.sh"

failed=0
IGNORE="$(cat "$here/../changes/ignore.txt")"
WORK_PATHS='' PATHS_REGEX=''

# case_ <expected: run|skip> <changed file>
case_() {
  local want=$1 got=skip
  if printf '%s\n' "$2" | decide > /dev/null; then got=run; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $want $2"
  else
    echo "FAIL $2: wanted $want, got $got"
    failed=1
  fi
}

COMPONENTS='platform/* apps/*/prod apps/*/staging' MANIFESTS=bootstrap
PATHS=$(component_paths)
want='platform/*/** apps/*/prod/** apps/*/*/** apps/*/staging/** bootstrap/**'
if [ "$PATHS" = "$want" ]; then echo "ok   paths"; else echo "FAIL paths: $PATHS"; failed=1; fi

case_ run  apps/payload/prod/kustomization.yaml
case_ run  apps/payload/base/deployment.yaml
case_ run  platform/traefik/values.yaml
case_ run  apps/payload/staging/kustomization.yaml
case_ run  bootstrap/prod/x.yaml
case_ skip apps/payload/README.md
case_ skip src/index.ts

COMPONENTS='platform/*' MANIFESTS=''
PATHS=$(component_paths)
if [ "$PATHS" = 'platform/*/**' ]; then echo "ok   defaults"; else echo "FAIL defaults: $PATHS"; failed=1; fi

[ "$failed" = 0 ] || exit 1
