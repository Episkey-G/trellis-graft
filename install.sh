#!/usr/bin/env bash
#
# install.sh — the only command a target repository needs.
#
#   1. brand-new repo      (.trellis/ missing)  -> trellis init with this workflow, then copy
#   2. first-time adoption (stock Trellis)      -> trellis update -s, swap workflow, then copy
#   3. later upgrade       (graft already there)-> identical to 2
#
# Scenarios 2 and 3 do exactly the same thing, so there is no --upgrade switch:
# adopting and upgrading are one command.
#
# This script never writes .trellis/workflow.md itself. It calls the official
# `trellis init` / `trellis workflow` to do that, and only orchestrates.
#
#HELP-END

set -euo pipefail

MARKETPLACE="gh:Episkey-G/trellis-graft"
REPO_URL="https://github.com/Episkey-G/trellis-graft.git"
WORKFLOW_ID="trellis-mattpocock"
MIN_TRELLIS="0.6.14"

TARGET=""
REF=""
PLATFORM="claude"
DRY_RUN=0

# Colours only when stdout is a terminal — otherwise piping to a log file
# embeds escape codes in it.
if [ -t 1 ]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; DIM=$'\033[90m'; RST=$'\033[0m'
else
  RED=''; GRN=''; YEL=''; BLU=''; DIM=''; RST=''
fi

die()  { printf '%serror:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
info() { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '  %sok%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s!!%s %s\n' "$YEL" "$RST" "$*"; }

# Runs a command inside $TARGET. Takes an argv array, never a string, so paths
# containing spaces or quotes survive; `eval` would mangle them.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry-run] (cd %s && %s)%s\n' "$DIM" "$TARGET" "$*" "$RST"
    return 0
  fi
  ( cd "$TARGET" && "$@" )
}

usage() {
  cat <<'USAGE'
usage: install.sh --target <repo-path> [options]

  --target   <path>   repository to install into (required)
  --ref      <ref>    git ref of trellis-graft to install from. Only applies when
                      this script fetches a copy; ignored (with a warning) when
                      you run it from an existing checkout.
  --platform <name>   AI platform flag for `trellis init` on a brand-new repo
                      (default: claude; e.g. cursor, codex, gemini)
  --dry-run           print what would happen; write nothing
  -h, --help          this message
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)   TARGET="${2:-}"; shift 2 ;;
    --ref)      REF="${2:-}"; shift 2 ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown argument: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------- preflight --

[ -n "$TARGET" ] || { usage >&2; die "--target is required"; }
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || die "target does not exist: $TARGET"

command -v trellis  >/dev/null 2>&1 || die "trellis CLI not on PATH — npm i -g @mindfoldhq/trellis"
command -v python3  >/dev/null 2>&1 || die "python3 not on PATH (Trellis needs it too)"
command -v git      >/dev/null 2>&1 || die "git not on PATH"

[ -d "$TARGET/.git" ] || die "not a git repository: $TARGET"

version_lt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

if [ -d "$TARGET/.trellis" ] && [ -f "$TARGET/.trellis/.version" ]; then
  have="$(tr -d '[:space:]' < "$TARGET/.trellis/.version")"
  if version_lt "$have" "$MIN_TRELLIS"; then
    info "target is on Trellis $have; this graft needs >= $MIN_TRELLIS — will be raised by 'trellis update'"
  fi
fi

# ------------------------------------------------------------------- source --

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP=""
# Install the trap BEFORE mktemp/clone: under `set -e` a failed clone (bad ref,
# no network) exits immediately, and a trap installed after it never fires.
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT

if [ -f "$HERE/index.json" ] && [ -d "$HERE/agents/claude" ]; then
  SRC="$HERE"                                        # running from a checkout
  [ -n "$REF" ] && warn "--ref $REF ignored: installing from the checkout at $HERE (git -C '$HERE' checkout '$REF' first if you meant that ref)"
else
  SRC="$(mktemp -d)"; CLEANUP="$SRC"
  info "fetching trellis-graft@${REF:-main}"
  git clone --depth 1 --branch "${REF:-main}" --quiet "$REPO_URL" "$SRC"
fi

GRAFT_VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"

# ----------------------------------------------------------------- scenario --

if [ ! -d "$TARGET/.trellis" ]; then
  SCENARIO="new"
elif grep -q 'MATTPOCOCK-GRAFT:START' "$TARGET/AGENTS.md" 2>/dev/null; then
  SCENARIO="upgrade"
else
  SCENARIO="adopt"
fi

case "$SCENARIO" in
  new)     info "scenario: brand-new repository" ;;
  adopt)   info "scenario: first-time adoption (stock Trellis present)" ;;
  upgrade) info "scenario: upgrade (graft already installed)" ;;
esac

# ------------------------------------------------------- workflow.md, official --
# Order matters: `trellis update` first, so scripts/hooks (the parsers) are on the
# new version BEFORE a workflow.md written in newer syntax lands. Reversing this
# gives you new syntax against an old parser.

if [ "$SCENARIO" = "new" ]; then
  # -y is required, not cosmetic: without it `trellis init` opens an interactive
  # prompt (statusLine, among others) and dies with ERR_USE_AFTER_CLOSE the moment
  # it runs anywhere without a TTY.
  run trellis init -y "--$PLATFORM" --workflow "$WORKFLOW_ID" --workflow-source "$MARKETPLACE"
else
  # -s = skip every file the user modified. In a graft repo those modified files
  # are exactly our customisations, so this updates scripts/hooks and leaves the
  # graft alone — and it is non-interactive, which is what makes it scriptable.
  run trellis update -s
  # workflow.md is always 'modified'; -f is the whole point of an upgrade.
  run trellis workflow -m "$MARKETPLACE" -t "$WORKFLOW_ID" -f
fi
ok "workflow.md handled by the official channel"

# ------------------------------------------------------------- the artifacts --

copy() {  # copy <src-rel> <dst-rel>
  local s="$SRC/$1" d="$TARGET/$2"
  [ -f "$s" ] || die "missing in source: $1"
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry-run] write %s%s\n' "$DIM" "$2" "$RST"; return 0; fi
  mkdir -p "$(dirname "$d")"
  cp "$s" "$d"
  ok "$2"
}

info "installing agent definitions, the /trellis:continue fix, and docs"
copy agents/claude/trellis-implement.md .claude/agents/trellis-implement.md
copy agents/claude/trellis-check.md     .claude/agents/trellis-check.md
copy agents/claude/trellis-research.md  .claude/agents/trellis-research.md
copy agents/channel/implement.md        .trellis/agents/implement.md
copy agents/channel/check.md            .trellis/agents/check.md
copy docs/agents/issue-tracker.md       docs/agents/issue-tracker.md
copy docs/agents/domain.md              docs/agents/domain.md

# Upstream bug, still live in 0.6.14: ai-tools.js sets cliFlag "claude" for Claude
# Code, so a fresh `trellis init --claude` writes `--platform claude` into
# /trellis:continue. The parser only matches "claude-code" / "Claude Code", so every
# platform-scoped step body is silently dropped — `--mode phase --step 2.2` returns
# 4 lines instead of 18. This copy carries the corrected value.
copy commands/claude/trellis/continue.md .claude/commands/trellis/continue.md

# --------------------------------------------------------- AGENTS.md, marker --
# Idempotent: replace between the markers if present, append if not. Appending
# always lands outside the <!-- TRELLIS --> managed block, which is what keeps
# `trellis update` classifying AGENTS.md as unchanged.

info "injecting AGENTS.md section"
if [ "$DRY_RUN" = 1 ]; then
  printf '  %s[dry-run] update AGENTS.md marker block to v=%s%s\n' "$DIM" "$GRAFT_VERSION" "$RST"
else
  was="$(python3 - "$TARGET/AGENTS.md" "$SRC/snippets/agents-md-section.md" "$GRAFT_VERSION" <<'PY'
import pathlib, re, sys

target, snippet_path, version = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
body = snippet_path.read_text(encoding="utf-8").strip()
block = f"<!-- MATTPOCOCK-GRAFT:START v={version} -->\n{body}\n<!-- MATTPOCOCK-GRAFT:END -->"

existing = target.read_text(encoding="utf-8") if target.exists() else ""
pattern = re.compile(r"<!-- MATTPOCOCK-GRAFT:START[^>]*-->.*?<!-- MATTPOCOCK-GRAFT:END -->", re.S)

m = pattern.search(existing)
if m:
    updated = pattern.sub(lambda _: block, existing, count=1)
    print(m.group(0).split("v=")[1].split(" ")[0])
else:
    updated = (existing.rstrip() + "\n\n" + block + "\n") if existing.strip() else block + "\n"
    print("(new)")

target.write_text(updated, encoding="utf-8")
PY
)"
  ok "AGENTS.md marker $was -> $GRAFT_VERSION"
fi

# ------------------------------------------------------------------ summary --

if [ "$DRY_RUN" = 1 ]; then
  printf '\n%sDry run complete.%s Nothing was written. Re-run without --dry-run to apply.\n' "$YEL" "$RST"
  exit 0
fi

cat <<EOF

${GRN}Done.${RST} trellis-graft $GRAFT_VERSION installed into $TARGET

Two things this script deliberately does NOT do — finish them by hand:

  1. Install the engineering skills (once per machine, shared by every repo):

     npx skills@latest add mattpocock/skills -g --copy -y -a claude-code \\
       -s grill-with-docs -s grilling -s domain-modeling -s to-spec -s to-tickets \\
       -s tdd -s implement -s code-review -s research -s diagnosing-bugs \\
       -s codebase-design -s prototype

     Repeat -s per skill; a comma-separated list silently falls through to a listing.
     Use -a claude-code, not -a claude, or it installs into ~20 agent directories.

  2. Start a NEW session in $TARGET. Agent and skill definitions are cached at
     session start, so the ones installed just now do not take effect until then.
EOF
