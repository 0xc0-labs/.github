#!/usr/bin/env bash
# The globs whose change makes kustomize-validate run, from $COMPONENTS and
# $MANIFESTS. Each component glob counts with everything under it, and so
# does everything under its parent's other children: `apps/*/prod` leaves
# `apps/<app>/base`, which its overlays include, outside its own glob.
set -euo pipefail
set -f

component_paths() {
  local g out=()
  for g in $COMPONENTS; do
    out+=("$g/**")
    if [ "${g%/*}" != "$g" ]; then out+=("${g%/*}/*/**"); fi
  done
  if [ -n "${MANIFESTS:-}" ]; then out+=("$MANIFESTS/**"); fi
  printf '%s\n' "${out[@]}" | awk '!seen[$0]++' | paste -sd' ' -
}
