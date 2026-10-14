#!/usr/bin/env bash
# Decides whether a push, a PR or a merge group changed anything a workflow
# cares about (README, Path gates). Prints `run=true` or `run=false` to
# $GITHUB_OUTPUT.
set -euo pipefail
# The globs are words: pathname expansion must leave them alone.
set -f

# A glob as an anchored extended regex: `**/` is any directories or none, `**`
# anything, `*` anything inside a directory, `?` one character of it.
glob_to_regex() {
  local glob=$1 re='' c i=0
  while [ "$i" -lt "${#glob}" ]; do
    c=${glob:i:1}
    case $c in
      '*')
        if [ "${glob:i:3}" = '**/' ]; then
          re+='(.*/)?'
          i=$((i + 2))
        elif [ "${glob:i:2}" = '**' ]; then
          re+='.*'
          i=$((i + 1))
        else
          re+='[^/]*'
        fi
        ;;
      '?') re+='[^/]' ;;
      '.' | '+' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|' | '\') re+="\\$c" ;;
      *) re+=$c ;;
    esac
    i=$((i + 1))
  done
  printf '^%s$\n' "$re"
}

# The regex of each glob in the arguments, one per line. A glob list is
# whitespace-separated; `#` starts a comment.
regexes() {
  local list line g
  for list in "$@"; do
    while IFS= read -r line; do
      line=${line%%#*}
      for g in $line; do
        glob_to_regex "$g"
      done
    done <<< "$list"
  done
}

matches_any() {
  local f=$1 re
  shift
  for re in "$@"; do
    if [[ $f =~ $re ]]; then return 0; fi
  done
  return 1
}

# Changed paths on stdin. Exit 0, printing the first one that counts, when
# one does; 1 when none does.
#   IGNORE      globs that never cause work
#   PATHS       when set, only these count (globs)
#   PATHS_REGEX when set, only what it matches counts (extended regex)
#   WORK_PATHS  always count, whatever the rest says
decide() {
  local f re ignore=() own=() keep=()
  while IFS= read -r re; do [ -z "$re" ] || ignore+=("$re"); done <<< "$(regexes "$IGNORE")"
  while IFS= read -r re; do [ -z "$re" ] || own+=("$re"); done <<< "$(regexes "${PATHS:-}")"
  while IFS= read -r re; do [ -z "$re" ] || keep+=("$re"); done <<< "$(regexes "${WORK_PATHS:-}")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "${#keep[@]}" -gt 0 ] && matches_any "$f" "${keep[@]}"; then
      echo "$f"; return 0
    fi
    if matches_any "$f" "${ignore[@]}"; then continue; fi
    if [ "${#own[@]}" -gt 0 ] && ! matches_any "$f" "${own[@]}"; then continue; fi
    if [ -n "${PATHS_REGEX:-}" ] && ! [[ $f =~ $PATHS_REGEX ]]; then continue; fi
    echo "$f"; return 0
  done
  return 1
}

# The compared commits, `<base> <head>`, or nothing when the event is not one
# that has a diff.
range() {
  case $GITHUB_EVENT_NAME in
    pull_request | pull_request_target)
      jq -r '"\(.pull_request.base.sha) \(.pull_request.head.sha)"' "$GITHUB_EVENT_PATH" ;;
    push)
      jq -r '"\(.before) \(.after)"' "$GITHUB_EVENT_PATH" ;;
    merge_group)
      jq -r '"\(.merge_group.base_sha) \(.merge_group.head_sha)"' "$GITHUB_EVENT_PATH" ;;
  esac
}

# The files of a compare, page by page. The self-hosted runners have curl and
# jq but not `gh`, which GitHub's own images carry.
compare_files() {
  local url="repos/$GITHUB_REPOSITORY/compare/$1...$2?per_page=100"
  if command -v gh > /dev/null; then
    gh api --paginate "$url" --jq '.files[]? | .filename, (.previous_filename // empty)'
    return
  fi
  local page=1 names
  while :; do
    names=$(curl -fsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_URL:-https://api.github.com}/$url&page=$page" \
      | jq -r '.files[]? | .filename, (.previous_filename // empty)') || return 1
    [ -n "$names" ] || break
    printf '%s\n' "$names"
    page=$((page + 1))
  done
}

result() {
  echo "run=$1" >> "$GITHUB_OUTPUT"
  printf '%s\n' "$2"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '**changes:** %s\n' "$2" >> "$GITHUB_STEP_SUMMARY"
  fi
}

main() {
  local base head files first err="${RUNNER_TEMP:-/tmp}/changes.err"
  read -r base head <<< "$(range)"
  if [ -z "${base:-}" ]; then
    result true "A $GITHUB_EVENT_NAME has no diff to read: the work runs."; return
  fi
  if [ -z "${base//0/}" ]; then
    result true "No previous commit to compare with: the work runs."; return
  fi
  # The base is the event's own: a PR's base, a push's previous commit, a merge
  # group's base. One GitHub cannot find, a force-push's, does the work.
  if ! files=$(compare_files "$base" "$head" 2> "$err"); then
    result true "Cannot compare $base...$head ($(head -n1 "$err")): the work runs."; return
  fi
  # The compare lists 3000 files at most: a longer list is cut short.
  if [ "$(printf '%s\n' "$files" | grep -c .)" -ge 3000 ]; then
    result true "3000 files or more changed: the work runs."; return
  fi
  IGNORE="$(cat "$IGNORE_FILE")"$'\n'"${SKIP_PATHS:-}"
  export IGNORE
  if first=$(printf '%s\n' "$files" | decide); then
    result true "$first changed: the work runs."
  else
    result false "Nothing the work cares about changed: its jobs are skipped."
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main
fi
