#!/usr/bin/env bash
# Cases for changes.sh's decision: `bash .github/actions/changes/test.sh`.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=changes.sh
. "$here/changes.sh"

failed=0
IGNORE="$(cat "$here/ignore.txt")"

# case <expected: run|skip> <description> <changed files, newline-separated>
case_() {
  local want=$1 what=$2 got=skip
  if printf '%s\n' "$3" | decide > /dev/null; then got=run; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $what"
  else
    echo "FAIL $what: wanted $want, got $got"
    failed=1
  fi
}

PATHS='' PATHS_REGEX='' WORK_PATHS=''
case_ skip 'only .claude' $'.claude/settings.json\n.claude/skills/x/SKILL.md'
case_ skip 'a root readme' 'README.md'
case_ skip 'a nested markdown file' 'apps/web/content/post.md'
case_ skip 'docs, odd, license' $'docs/design.md\nodd/tasks/f.txt\nLICENSE'
case_ run  'code' 'src/index.ts'
case_ run  'code beside ignored files' $'.claude/settings.json\nsrc/index.ts'
case_ run  'a workflow' '.github/workflows/ci.yml'
case_ run  'a file that only looks ignored' 'docs.txt'
case_ run  'a nested LICENSE is not the root one' 'vendor/LICENSE'
case_ skip 'nothing changed' ''

PATHS='app/** mise.toml'
case_ skip 'outside the workflow paths' 'other/index.ts'
case_ run  'inside the workflow paths' 'app/src/index.ts'
case_ run  'a root file the workflow names' 'mise.toml'
case_ skip 'ignored inside the workflow paths' 'app/README.md'

PATHS='' PATHS_REGEX='^(environments/|modules/)'
case_ run  'a regex match' 'modules/vm/main.tf'
case_ skip 'no regex match' 'scripts/tofu'
case_ skip 'ignored under the regex' 'modules/vm/README.md'

PATHS='' PATHS_REGEX='' WORK_PATHS='content/**/*.md plugins/**'
case_ run  'work-paths bring back an ignored file' 'content/blog/post.md'
case_ run  'work-paths in a plugin' 'plugins/x/skills/y/SKILL.md'
case_ skip 'work-paths leave the rest alone' 'docs/design.md'

IGNORE="$(cat "$here/ignore.txt")"$'\n''generated/**'
WORK_PATHS=''
case_ skip 'skip-paths widen the ignores' 'generated/api/client.ts'
case_ run  'and leave the rest' 'src/client.ts'

[ "$failed" = 0 ] || exit 1
