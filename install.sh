#!/usr/bin/env bash
#
# install.sh — the only command a target repository needs.
#
# Covers three scenarios and picks the right one itself:
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

set -euo pipefail

MARKETPLACE="gh:Episkey-G/trellis-graft"
REPO_URL="https://github.com/Episkey-G/trellis-graft.git"
WORKFLOW_ID="trellis-mattpocock"
MIN_TRELLIS="0.6.14"

TARGET=""
REF="main"
PLATFORM="claude"
DRY_RUN=0

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  \033[90m[dry-run] %s\033[0m\n' "$*"; else eval "$@"; fi; }

usage() {
  cat <<'USAGE'
usage: install.sh --target <repo-path> [options]

  --target   <path>   repository to install into (required)
  --ref      <ref>    git ref of trellis-graft to install from (default: main)
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
if [ -f "$HERE/index.json" ] && [ -d "$HERE/agents/claude" ]; then
  SRC="$HERE"                                        # running from a checkout
else
  SRC="$(mktemp -d)"; CLEANUP="$SRC"
  info "fetching trellis-graft@$REF"
  git clone --depth 1 --branch "$REF" --quiet "$REPO_URL" "$SRC"
fi
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT

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
  run "(cd '$TARGET' && trellis init -y --$PLATFORM --workflow '$WORKFLOW_ID' --workflow-source '$MARKETPLACE')"
else
  # -s = skip every file the user modified. In a graft repo those modified files
  # are exactly our customisations, so this updates scripts/hooks and leaves the
  # graft alone — and it is non-interactive, which is what makes it scriptable.
  run "(cd '$TARGET' && trellis update -s)"
  # workflow.md is always 'modified'; -f is the whole point of an upgrade.
  run "(cd '$TARGET' && trellis workflow -m '$MARKETPLACE' -t '$WORKFLOW_ID' -f)"
fi
ok "workflow.md handled by the official channel"

# ------------------------------------------------------------- the 7 artifacts --

copy() {  # copy <src-rel> <dst-rel>
  local s="$SRC/$1" d="$TARGET/$2"
  [ -f "$s" ] || die "missing in source: $1"
  if [ "$DRY_RUN" = 1 ]; then printf '  \033[90m[dry-run] write %s\033[0m\n' "$2"; return; fi
  mkdir -p "$(dirname "$d")"
  cp "$s" "$d"
  printf '  \033[32mok\033[0m %s\n' "$2"
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
  printf '  \033[90m[dry-run] update AGENTS.md marker block to v=%s\033[0m\n' "$GRAFT_VERSION"
else
  python3 - "$TARGET/AGENTS.md" "$SRC/snippets/agents-md-section.md" "$GRAFT_VERSION" <<'PY'
import pathlib, re, sys

target, snippet_path, version = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
body = snippet_path.read_text(encoding="utf-8").strip()
block = f"<!-- MATTPOCOCK-GRAFT:START v={version} -->\n{body}\n<!-- MATTPOCOCK-GRAFT:END -->"

existing = target.read_text(encoding="utf-8") if target.exists() else ""
pattern = re.compile(r"<!-- MATTPOCOCK-GRAFT:START[^>]*-->.*?<!-- MATTPOCOCK-GRAFT:END -->", re.S)

was = m.group(0).split("v=")[1].split(" ")[0] if (m := pattern.search(existing)) else None
if m:
    updated = pattern.sub(lambda _: block, existing, count=1)
else:
    updated = (existing.rstrip() + "\n\n" + block + "\n") if existing.strip() else block + "\n"

target.write_text(updated, encoding="utf-8")
print(f"  \033[32mok\033[0m AGENTS.md marker {was or '(new)'} -> {version}")
PY
fi

# ------------------------------------------------------------------ summary --

cat <<EOF

$(printf '\033[32mDone.\033[0m') trellis-graft $GRAFT_VERSION installed into $TARGET

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
