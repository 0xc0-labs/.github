#!/usr/bin/env bash
# The pins step of pin-check.yml: each environment's images under
# ghcr.io/<owner>/ are one application's, and each newTag is APP_VERSION
# (README, Application repos). Sourced by action.yml and by test.sh.

# The application's base among image names, one a line, the owner's prefix
# already stripped: the shortest name when every other is `<it>-<suffix>`;
# else, for an application with no image of its own, the longest prefix of
# whole `-` words they all share. Prints nothing when they share none.
application_base() {
  local names=$1 base name alone=1 i first=1
  local -a common=() words=()
  base=$(printf '%s\n' "$names" | awk '{ print length($0) " " $0 }' | sort -n | head -n1 | cut -d' ' -f2-)
  while read -r name; do
    if [ "$name" != "$base" ] && [[ "$name" != "$base"-?* ]]; then alone=0; fi
  done <<< "$names"
  if [ "$alone" = 1 ]; then
    printf '%s\n' "$base"
    return
  fi
  while read -r name; do
    IFS=- read -r -a words <<< "$name"
    if [ "$first" = 1 ]; then
      common=("${words[@]}")
      first=0
      continue
    fi
    for i in "${!common[@]}"; do
      if [ "${words[i]:-}" != "${common[i]}" ]; then
        common=("${common[@]:0:i}")
        break
      fi
    done
    [ "${#common[@]}" -gt 0 ] || return 0
  done <<< "$names"
  local joined=${common[0]}
  for ((i = 1; i < ${#common[@]}; i++)); do joined="$joined-${common[i]}"; done
  printf '%s\n' "$joined"
}

# check_images <pin> <version> <owner>, the `<name> <newTag>` rows of the
# pin's images under ghcr.io/<owner>/ on stdin. Returns 1 on any error.
check_images() {
  local pin=$1 version=$2 owner=$3 prefix="ghcr.io/$3/"
  local rows names base name tag status=0
  rows=$(cat)
  if [ -z "$rows" ]; then
    echo "::error file=$pin::APP_VERSION is $version, and no image is under ghcr.io/$owner/."
    return 1
  fi
  names=$(printf '%s\n' "$rows" | cut -d' ' -f1 | sed "s|^$prefix||")
  base=$(application_base "$names")
  if [ -z "$base" ]; then
    echo "::error file=$pin::The images under ghcr.io/$owner/ are not one application's: none is the base of the others, and they share no leading word."
    return 1
  fi
  while read -r name tag; do
    name=${name#"$prefix"}
    if [ "$name" != "$base" ] && [[ "$name" != "$base"-?* ]]; then
      echo "::error file=$pin::$prefix$name is not the application's: its images under ghcr.io/$owner/ are $base and $base-<suffix> alone."
      status=1
    elif [ "$tag" != "$version" ]; then
      echo "::error file=$pin::APP_VERSION is $version, but the newTag of $prefix$name is ${tag:-unset}."
      status=1
    else
      echo "$pin: $prefix$name $version"
    fi
  done <<< "$rows"
  return $status
}

# check_pins <owner> <pin>...: the whole step, with yq on the PATH.
check_pins() {
  local owner=$1 pin version status=0
  shift
  for pin in "$@"; do
    [ -f "$pin" ] || continue
    version=$(yq '[.configMapGenerator[] | select(.name == "release") | .literals[] | select(test("^APP_VERSION=")) | sub("^APP_VERSION="; "")] | .[0] // ""' "$pin")
    [ -n "$version" ] || continue
    OWNER=$owner yq '[.images[] | select(.name | test("^ghcr\\.io/" + strenv(OWNER) + "/"))] | .[] | .name + " " + (.newTag // "")' "$pin" |
      check_images "$pin" "$version" "$owner" || status=1
  done
  return $status
}
