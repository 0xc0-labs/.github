#!/usr/bin/env bash
# Cases for pin-check.sh: `bash .github/actions/pin-check/test.sh`.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=pin-check.sh
. "$here/pin-check.sh"

failed=0
P=ghcr.io/0xc0-labs

# case_ <expected: pass|fail> <description> <APP_VERSION> <rows...>
case_() {
  local want=$1 desc=$2 version=$3 got=fail out
  shift 3
  if out=$(printf '%s\n' "$@" | check_images pin.yaml "$version" 0xc0-labs); then got=pass; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $want $desc"
  else
    echo "FAIL $desc: wanted $want, got $got"
    printf '%s\n' "$out"
    failed=1
  fi
}

case_ pass "one image alone"                      v1.0.0 "$P/offby1.cc v1.0.0"
case_ pass "own image with a second"              v1.0.0 "$P/art v1.0.0" "$P/art-cms v1.0.0"
case_ pass "own image with two seconds"           v1.0.0 "$P/art-cms v1.0.0" "$P/art v1.0.0" "$P/art-web v1.0.0"
case_ pass "per-service images, no own image"     v0.2.0 "$P/matchmark-api v0.2.0" "$P/matchmark-stand-in-provider v0.2.0"
case_ pass "three per-service images"             v0.2.0 "$P/matchmark-api v0.2.0" "$P/matchmark-web v0.2.0" "$P/matchmark-stand-in-provider v0.2.0"
case_ fail "per-service beside another app"       v0.2.0 "$P/matchmark-api v0.2.0" "$P/offby1.cc v0.2.0"
case_ fail "own image beside another app"         v1.0.0 "$P/art v1.0.0" "$P/art-cms v1.0.0" "$P/offby1.cc v1.0.0"
case_ fail "own image with unrelated per-service" v1.0.0 "$P/art v1.0.0" "$P/matchmark-api v1.0.0"
case_ fail "no common word"                       v1.0.0 "$P/foo-api v1.0.0" "$P/bar-api v1.0.0"
case_ fail "a prefix of letters is not a word"    v1.0.0 "$P/match-api v1.0.0" "$P/matchmark-api v1.0.0"
case_ fail "stale newTag, own image"              v1.1.0 "$P/art v1.1.0" "$P/art-cms v1.0.0"
case_ fail "stale newTag, per-service"            v0.2.0 "$P/matchmark-api v0.2.0" "$P/matchmark-stand-in-provider v0.1.0"
case_ fail "unset newTag"                         v0.2.0 "$P/matchmark-api v0.2.0" "$P/matchmark-web "
case_ fail "no image under the owner"             v1.0.0 ""

base=$(application_base $'matchmark-api\nmatchmark-stand-in-provider')
if [ "$base" = matchmark ]; then echo "ok   base matchmark"; else echo "FAIL base: '$base'"; failed=1; fi
base=$(application_base $'art\nart-cms')
if [ "$base" = art ]; then echo "ok   base art"; else echo "FAIL base: '$base'"; failed=1; fi

exit $failed
