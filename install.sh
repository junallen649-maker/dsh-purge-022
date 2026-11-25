#!/usr/bin/env bash
# install.sh -- dsh-purge for `dsh web` on macOS / Linux.
#
#   ./install.sh                    # profile web (default)
#   ./install.sh --profile desktop
#   ./install.sh --dsh-home ~/.dsh
#   ./install.sh --dry-run
#
# Everything is local: no npm install, no network. The plugin body, the 0.2.2
# re-fitted patch table and the profile manifests all live in payload/.

set -euo pipefail

PROFILE="web"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
DRY=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   PROFILE="$2"; shift 2 ;;
    --dsh-home)  DSH_HOME="$2"; shift 2 ;;
    --dry-run)   DRY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n[%s] %s\n' "$1" "$2"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$HERE/payload/plugin" ] || die "payload/plugin missing next to this script"

# ---------------------------------------------------------------- [1/6] host
step "1/6" "locating @deepseek-ai ..."
AI_BASE=""
for cand in \
  "$(npm root -g 2>/dev/null || true)/@deepseek-ai" \
  "$DSH_HOME/node_modules/@deepseek-ai" \
  "$DSH_HOME/profiles/$PROFILE/node_modules/@deepseek-ai" \
  "/usr/local/lib/node_modules/@deepseek-ai" \
  "/usr/lib/node_modules/@deepseek-ai"
do
  if [ -n "$cand" ] && [ -f "$cand/dsh-agent-instructions/lib/index.js" ]; then
    AI_BASE="$cand"; break
  fi
done
[ -n "$AI_BASE" ] || die "cannot find @deepseek-ai -- set npm prefix, or install dsh web first"
say "root: $AI_BASE"

NODE="$(command -v node || true)"
[ -n "$NODE" ] || die "node not found on PATH"

# -------------------------------------------------------------- [2/6] build
step "2/6" "reading build ..."
VER=""
for p in "$AI_BASE/dsh-base/package.json" "$AI_BASE/dsh/package.json"; do
  if [ -f "$p" ]; then
    VER="$("$NODE" -e 'const p=require(process.argv[1]);console.log(p.version||"")' "$p" 2>/dev/null || true)"
    [ -n "$VER" ] && break
  fi
done
[ -n "$VER" ] || die "cannot read harness version from $AI_BASE"
say "host $VER"

TABLE=""
case "$VER" in
  0.2.2*)   TABLE="$HERE/payload/core-022.js" ;;
  0.2.1*)   TABLE="" ;;
  *)        say "WARNING: $VER untested (0.2.1.x / 0.2.2.x are tested)" ;;
esac
if [ -n "$TABLE" ]; then say "patch table: re-fit for 0.2.2"; else say "patch table: upstream 1.1.90"; fi

# ------------------------------------------------------------ [3/6] install
step "3/6" "installing plugin ..."
PLUG="$DSH_HOME/plugins/dsh-purge"
if [ "$DRY" = "1" ]; then
  say "would install plugin -> $PLUG"
else
  rm -rf "$PLUG"
  mkdir -p "$(dirname "$PLUG")"
  cp -R "$HERE/payload/plugin" "$PLUG"
  if [ -n "$TABLE" ]; then
    cp "$TABLE" "$PLUG/lib/core.js"
    say "core.js -> 0.2.2 re-fit table"
  fi
fi

PROF="$DSH_HOME/profiles/$PROFILE"
if [ "$DRY" = "1" ]; then
  say "would mount profile -> $PROF"
else
  mkdir -p "$PROF/node_modules"
  rm -f "$PROF/node_modules/.modules.yaml" "$PROF/node_modules/.pnpm-workspace-state-v1.json"
  SRC="$HERE/payload/profiles/$PROFILE"
  [ -d "$SRC" ] || SRC="$HERE/payload/profiles/web"
  cp "$SRC/package.json" "$PROF/package.json"
  cp "$SRC/cordis.patch.yml" "$PROF/cordis.patch.yml"
  [ -f "$SRC/pnpm-workspace.yaml" ] && cp "$SRC/pnpm-workspace.yaml" "$PROF/pnpm-workspace.yaml"
  rm -rf "$PROF/node_modules/dsh-purge"
  cp -R "$PLUG" "$PROF/node_modules/dsh-purge"
  say "profile $PROFILE mounted"
fi

# stale stamps from other machines
for f in applied.json installed-rev override-state.json unpacked-asar.json \
         version-history.json auto-update-guard.json settle-restart.guard \
         last-cwd.txt channel.json; do
  [ "$DRY" = "1" ] || rm -f "$DSH_HOME/dsh-purge/$f"
done

# -------------------------------------------------------------- [4/6] apply
step "4/6" "applying patches ..."
CLI="$PLUG/bin/dsh-purge.js"
LOG_DIR="$DSH_HOME/dsh-purge"
if [ "$DRY" = "1" ]; then
  say "would run: node $CLI --apply"
else
  mkdir -p "$LOG_DIR"
  LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
  DSH_SURFACE=web DSH_BASE="$AI_BASE" DSH_HOME="$DSH_HOME" \
    "$NODE" "$CLI" --apply >"$LOG" 2>&1 || true
  grep -E '已清洗|待清洗|文件缺失' "$LOG" | tail -n 3 || tail -n 8 "$LOG"
  say "log: $LOG"
fi

# ------------------------------------------------------------- [5/6] preset
step "5/6" "preset ..."
PRESET="$DSH_HOME/.agent-presets/redteam/agent.cordis.yml"
if [ -f "$PRESET" ] && [ "$DRY" != "1" ]; then
  if grep -q 'tool-subagent-list-agents' "$PRESET" || grep -q 'workflow-worker-thread' "$PRESET"; then
    cp "$PRESET" "$PRESET.bak-$(date +%Y%m%d-%H%M%S)"
    "$NODE" - "$PRESET" <<'JS'
const fs = require('fs');
const file = process.argv[2];
const keep = [];
const skipIds = new Set(['tool-subagent-list-agents', 'workflow-worker-thread']);
let lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
let out = [], i = 0, removed = 0;
while (i < lines.length) {
  const m = /^(\s*)-\s+id:\s*(\S+)\s*$/.exec(lines[i]);
  if (!m || !skipIds.has(m[2])) { out.push(lines[i++]); continue; }
  const indent = m[1].length; i++; removed++;
  while (i < lines.length) {
    const l = lines[i];
    if (l.trim() === '') { i++; continue; }
    const cur = l.length - l.trimStart().length;
    if (cur > indent) { i++; continue; }
    if (cur === indent && l.trimStart().startsWith('#')) { i++; continue; }
    break;
  }
}
fs.writeFileSync(file, out.join('\n'), 'utf8');
console.log('      preset: removed ' + removed + ' block(s)');
JS
  else
    say "preset: already clean"
  fi
elif [ ! -f "$PRESET" ]; then
  say "no redteam preset yet (it is created when the plugin first loads)"
fi

# ------------------------------------------------------------- [6/6] verify
step "6/6" "verify ..."
if [ "$DRY" != "1" ] && [ -f "$CLI" ]; then
  DSH_SURFACE=web DSH_BASE="$AI_BASE" DSH_HOME="$DSH_HOME" \
    "$NODE" "$CLI" --status 2>/dev/null | grep -E '补丁|宿主版本' || true
fi

printf '\nDONE. Restart dsh web, then run /purge status in a chat.\n'
