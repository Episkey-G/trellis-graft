#!/usr/bin/env bash
#
# upgrade.sh — the only command this repository needs when Trellis ships a new version.
#
#   ./upgrade.sh                  follow npm's `latest`
#   ./upgrade.sh 0.7.0-beta.3     or a specific version
#   ./upgrade.sh --continue       resume after resolving conflicts by hand
#
# It runs all five steps in order, so there is no second command to remember:
#
#   1. upgrade the global Trellis CLI
#   2. fetch that version's pristine templates  (npm pack — no install needed)
#   3. three-way merge each grafted file        (BASE=upstream/, OURS=ours, THEIRS=new)
#   4. validate the five parser-sensitive structures
#   5. refresh upstream/ to the new BASE, bump VERSION, print the git commands
#
# Step 5 prints the git commands rather than running them. Publishing is a decision.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

STATE=".upgrade-state"
TARGET_VERSION="latest"
RESUME=0

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\n\033[34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!!\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --continue) RESUME=1; shift ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "unknown argument: $1" ;;
    *)          TARGET_VERSION="$1"; shift ;;
  esac
done

command -v npm >/dev/null 2>&1 || die "npm not on PATH"
command -v git >/dev/null 2>&1 || die "git not on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"

# Each grafted file, as "<our path>|<path inside dist/templates>".
FILES=(
  "workflows/trellis-mattpocock/workflow.md|trellis/workflow.md"
  "agents/claude/trellis-implement.md|claude/agents/trellis-implement.md"
  "agents/claude/trellis-check.md|claude/agents/trellis-check.md"
  "agents/claude/trellis-research.md|claude/agents/trellis-research.md"
  "agents/channel/check.md|trellis/agents/check.md"
  "agents/channel/implement.md|trellis/agents/implement.md"
  "commands/claude/trellis/continue.md|common/commands/continue.md"
)

# ------------------------------------------------------------------ resume --

if [ "$RESUME" = 1 ]; then
  [ -f "$STATE" ] || die "no upgrade in progress (no $STATE) — run without --continue"
  # shellcheck disable=SC1090
  . "$STATE"
  [ -d "$NEW_TEMPLATES" ] || die "the fetched templates are gone; rerun without --continue"
  if grep -rl '^<<<<<<< ' "${FILES[@]%%|*}" 2>/dev/null | grep -q .; then
    die "conflict markers still present in: $(grep -rl '^<<<<<<< ' "${FILES[@]%%|*}" | tr '\n' ' ')"
  fi
  info "resuming at step 4 for Trellis $RESOLVED_VERSION"
else

# ------------------------------------------------- 1. upgrade the global CLI --

  info "step 1/5 — upgrading the global Trellis CLI to $TARGET_VERSION"
  npm i -g "@mindfoldhq/trellis@$TARGET_VERSION" >/dev/null
  RESOLVED_VERSION="$(trellis --version | tr -d '[:space:]')"
  ok "trellis $RESOLVED_VERSION"

  OLD_VERSION="$(tr -d '[:space:]' < upstream/VERSION)"
  if [ "$OLD_VERSION" = "$RESOLVED_VERSION" ]; then
    printf '\n\033[32mAlready current.\033[0m upstream/ is already at %s — nothing to merge.\n' "$OLD_VERSION"
    exit 0
  fi
  info "moving BASE from $OLD_VERSION to $RESOLVED_VERSION"

# ----------------------------------------------------- 2. fetch new templates --

  info "step 2/5 — fetching pristine templates for $RESOLVED_VERSION"
  WORK="$(mktemp -d)"
  ( cd "$WORK" && npm pack "@mindfoldhq/trellis@$RESOLVED_VERSION" --silent >/dev/null \
      && tar -xzf ./*.tgz )
  NEW_TEMPLATES="$WORK/package/dist/templates"
  [ -d "$NEW_TEMPLATES" ] || die "dist/templates not found in the packed tarball"
  ok "templates at $NEW_TEMPLATES"

# --------------------------------------------------------- 3. three-way merge --

  info "step 3/5 — three-way merge"
  CONFLICTED=""
  for entry in "${FILES[@]}"; do
    ours="${entry%%|*}"; rel="${entry##*|}"
    base="upstream/$rel"
    theirs="$NEW_TEMPLATES/$rel"
    [ -f "$theirs" ] || { warn "$rel vanished upstream — review by hand"; CONFLICTED="$CONFLICTED $ours"; continue; }

    # continue.md ships with {{PYTHON_CMD}} / {{CLI_FLAG}} placeholders that init
    # substitutes. Substitute both sides identically so the merge compares real
    # changes instead of re-conflicting on the placeholder every single time.
    b="$(mktemp)"; t="$(mktemp)"
    python3 - "$base" "$b" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.write_text(src.read_text(encoding="utf-8")
               .replace("{{PYTHON_CMD}}", "python3")
               .replace("{{CLI_FLAG}}", "claude-code"), encoding="utf-8")
PY
    python3 - "$theirs" "$t" <<'PY'
import pathlib, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.write_text(src.read_text(encoding="utf-8")
               .replace("{{PYTHON_CMD}}", "python3")
               .replace("{{CLI_FLAG}}", "claude-code"), encoding="utf-8")
PY

    if cmp -s "$b" "$t"; then
      ok "$rel — upstream unchanged"
    elif git merge-file --diff3 -L ours -L base -L upstream "$ours" "$b" "$t"; then
      ok "$rel — merged cleanly"
    else
      n="$(grep -c '^<<<<<<< ' "$ours" || true)"
      warn "$rel — $n conflict(s) in $ours"
      CONFLICTED="$CONFLICTED $ours"
    fi
    rm -f "$b" "$t"
  done

  if [ -n "$CONFLICTED" ]; then
    {
      printf 'RESOLVED_VERSION=%s\n' "$RESOLVED_VERSION"
      printf 'NEW_TEMPLATES=%s\n' "$NEW_TEMPLATES"
    } > "$STATE"
    cat <<EOF

$(printf '\033[33mStopped at step 3.\033[0m') Conflicts in:$CONFLICTED

Each conflict block shows three sections: ours / base / upstream. Keep your graft's
intent, take upstream's structural changes. Conflicts land only where you edited —
if one shows up inside '## Phase Index' or a [workflow-state:*] block, look twice,
that is unusual.

Then:  ./upgrade.sh --continue
EOF
    exit 1
  fi
fi

# ------------------------------------------------------------- 4. validate --

info "step 4/5 — validating the parser contract"
python3 - "workflows/trellis-mattpocock/workflow.md" <<'PY'
import pathlib, re, sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
failures = []

if not re.search(r'^## Phase Index$', text, re.M):
    failures.append("missing the exact heading '## Phase Index'")
if not re.search(r'^## Phase 1: Plan$', text, re.M):
    failures.append("missing the exact heading '## Phase 1: Plan'")

opened = re.findall(r'^\[workflow-state:([A-Za-z0-9_-]+)\]$', text, re.M)
closed = re.findall(r'^\[/workflow-state:([A-Za-z0-9_-]+)\]$', text, re.M)
if opened != closed:
    failures.append(f"workflow-state tags unbalanced: open={opened} close={closed}")

plat_open = [m for m in re.findall(r'^\[([A-Za-z][^\]/]*)\]$', text, re.M) if 'workflow-state' not in m]
plat_close = [m for m in re.findall(r'^\[/([A-Za-z][^\]]*)\]$', text, re.M) if 'workflow-state' not in m]
if plat_open != plat_close:
    failures.append(f"platform markers unbalanced: {len(plat_open)} open vs {len(plat_close)} close")

steps = re.findall(r'^#### (\d+\.\d+)', text, re.M)
if not steps:
    failures.append("no '#### X.Y' step headings found")

for name in ("no_task", "planning", "in_progress"):
    m = re.search(rf'^\[workflow-state:{name}\]$(.*?)^\[/workflow-state:{name}\]$', text, re.S | re.M)
    if not m or not m.group(1).strip():
        failures.append(f"[workflow-state:{name}] is missing or empty")

if failures:
    print("\033[31m  FAILED\033[0m")
    for f in failures:
        print(f"    - {f}")
    sys.exit(1)

print(f"  \033[32mok\033[0m {len(opened)} workflow-state pairs, "
      f"{len(plat_open)} platform markers, {len(steps)} steps: {' '.join(steps)}")
PY

cat <<'EOF'
  note  this checks the five parser-sensitive structures the Trellis docs define.
        The end-to-end check is `get_context.py --mode phase --step X.Y
        --platform claude-code` inside a real project — run it after install.sh.
EOF

# ------------------------------------------------- 5. refresh BASE and report --

info "step 5/5 — refreshing the merge baseline"
for entry in "${FILES[@]}"; do
  rel="${entry##*|}"
  mkdir -p "upstream/$(dirname "$rel")"
  cp "$NEW_TEMPLATES/$rel" "upstream/$rel"
done
printf '%s\n' "$RESOLVED_VERSION" > upstream/VERSION
ok "upstream/ now mirrors Trellis $RESOLVED_VERSION"

OLD_GRAFT="$(tr -d '[:space:]' < VERSION)"
NEW_GRAFT="$(python3 -c "
major, minor, patch = '$OLD_GRAFT'.split('.')
print(f'{major}.{int(minor) + 1}.0')")"
printf '%s\n' "$NEW_GRAFT" > VERSION
ok "graft version $OLD_GRAFT -> $NEW_GRAFT"

rm -f "$STATE"

cat <<EOF

$(printf '\033[32mUpgrade complete.\033[0m') graft $NEW_GRAFT tracks Trellis $RESOLVED_VERSION

Review the diff, then publish:

  git diff
  git add -A && git commit -m "chore: track Trellis $RESOLVED_VERSION"
  git tag v$NEW_GRAFT && git push && git push --tags

Then in each consuming repository:

  /path/to/trellis-graft/install.sh --target .
EOF
