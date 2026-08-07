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
# It never needs to be copied into the target repository. Three ways to reach it:
#
#   ./install.sh --target <repo>                    from a checkout
#   ln -s "$PWD/install.sh" ~/.local/bin/trellis-graft   then `trellis-graft` in any repo
#   curl -fsSL <raw-url>/install.sh | bash -s -- --target .   no checkout at all
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
usage: install.sh [--target <repo-path>] [options]

  --target   <path>   repository to install into (default: current directory)
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

[ -n "$TARGET" ] || TARGET="$PWD"
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || die "target does not exist: $TARGET"

command -v trellis  >/dev/null 2>&1 || die "trellis CLI not on PATH — npm i -g @mindfoldhq/trellis"
command -v python3  >/dev/null 2>&1 || die "python3 not on PATH (Trellis needs it too)"
command -v git      >/dev/null 2>&1 || die "git not on PATH"

# Trellis itself does not require a repository — `trellis init` works in a plain
# directory — so this is a warning rather than a gate; nothing this script writes
# needs git. What needs it is the workflow afterwards: Phase 2.2 dispatches
# trellis-check with a fixed point and it runs `git diff <ref>...HEAD`, and Phase 3.4
# is a commit. Both are dead in a non-repo, so say so once, here.
if [ ! -d "$TARGET/.git" ]; then
  warn "not a git repository: $TARGET"
  warn "installing anyway — but Phase 2.2 (trellis-check diffs against a fixed point) and Phase 3.4 (commit) stay broken until you run 'git init'"
fi

version_lt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && [ "$1" != "$2" ]; }

if [ -d "$TARGET/.trellis" ] && [ -f "$TARGET/.trellis/.version" ]; then
  have="$(tr -d '[:space:]' < "$TARGET/.trellis/.version")"
  if version_lt "$have" "$MIN_TRELLIS"; then
    info "target is on Trellis $have; this graft needs >= $MIN_TRELLIS — will be raised by 'trellis update'"
  fi
fi

# ------------------------------------------------------------------- source --

# Directory of the real script, symlinks resolved. Without the resolve loop a
# `~/.local/bin/trellis-graft -> ~/trellis-graft/install.sh` symlink reports
# ~/.local/bin, the checkout probe below misses, and every run silently re-clones
# from the remote — ignoring whatever is in the checkout you meant to install.
script_dir() {
  local src="$1" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac   # link target may be relative
  done
  ( cd -P "$(dirname "$src")" && pwd )
}

# Empty when the script arrives on stdin (`curl … | bash`): there is no checkout
# to install from, so the branch below fetches one. Defaulting to $PWD here would
# make the install source depend on which directory you happened to stand in.
SELF="${BASH_SOURCE[0]:-}"
HERE=""
if [ -n "$SELF" ]; then HERE="$(script_dir "$SELF")"; fi

CLEANUP=""
# Install the trap BEFORE mktemp/clone: under `set -e` a failed clone (bad ref,
# no network) exits immediately, and a trap installed after it never fires.
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT

if [ -n "$HERE" ] && [ -f "$HERE/index.json" ] && [ -d "$HERE/agents/claude" ]; then
  SRC="$HERE"                                        # running from a checkout
  [ -n "$REF" ] && warn "--ref $REF ignored: installing from the checkout at $HERE (git -C '$HERE' checkout '$REF' first if you meant that ref)"
else
  SRC="$(mktemp -d)"; CLEANUP="$SRC"
  info "fetching trellis-graft@${REF:-main}"
  git clone --depth 1 --branch "${REF:-main}" --quiet "$REPO_URL" "$SRC"
fi

# --target defaults to $PWD, so a bare run inside this repo would otherwise try
# to graft trellis-graft onto itself.
[ "$TARGET" != "$SRC" ] || die "target is the trellis-graft checkout itself — pass --target <repo-path>"

GRAFT_VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"

# ----------------------------------------------------------------- scenario --

# The AGENTS.md marker is the primary signal, but it only exists from 1.0.0 on and
# a repo can lose it (hand-copied artifacts, a rewritten AGENTS.md). Keying on it
# alone reports "first-time adoption" while the copies below overwrite real files —
# and a user who reads "first-time" has no reason to review that diff. So fall back
# to traces the graft leaves in files Trellis also owns:
#   - docs/agents/ — created only by this script
#   - the `Skill` entry in trellis-implement.md's tools: upstream ships the same
#     path without it, so its presence cannot come from `trellis init`
graft_artifacts_present() {
  if [ -f "$TARGET/docs/agents/issue-tracker.md" ]; then return 0; fi
  grep -q '^tools:.*\bSkill\b' "$TARGET/.claude/agents/trellis-implement.md" 2>/dev/null
}

MARKER_MISSING=0
if [ ! -d "$TARGET/.trellis" ]; then
  SCENARIO="new"
elif grep -q 'MATTPOCOCK-GRAFT:START' "$TARGET/AGENTS.md" 2>/dev/null; then
  SCENARIO="upgrade"
elif graft_artifacts_present; then
  SCENARIO="upgrade"; MARKER_MISSING=1
else
  SCENARIO="adopt"
fi

case "$SCENARIO" in
  new)     info "scenario: brand-new repository" ;;
  adopt)   info "scenario: first-time adoption (stock Trellis present)" ;;
  upgrade) info "scenario: upgrade (graft already installed)" ;;
esac
# Plain `[ … ] && warn` would return non-zero when the marker is present, and
# under `set -e` that ends the run right here.
if [ "$MARKER_MISSING" = 1 ]; then
  warn "graft artifacts found without an AGENTS.md marker — hand-installed, or the marker was removed. This run overwrites them; review the diff afterwards."
fi

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

# Codex, only when `trellis init` configured it. Same three roles as Claude, in Codex's
# .toml format. The check agent is the one that really differs: upstream ships it
# workspace-write and self-fixing, this one is sandbox_mode = "read-only" and single-axis,
# which is a harder guarantee than Claude's tools: allowlist — the sandbox refuses the
# write rather than the prompt asking it not to.
if [ -d "$TARGET/.codex/agents" ]; then
  copy agents/codex/trellis-implement.toml .codex/agents/trellis-implement.toml
  copy agents/codex/trellis-check.toml     .codex/agents/trellis-check.toml
  copy agents/codex/trellis-research.toml  .codex/agents/trellis-research.toml
fi

# The shared skill layer (.agents/skills/) is what Codex reads for /trellis-continue —
# Claude uses .claude/commands/trellis/continue.md instead. Both inherited upstream's
# "load trellis-brainstorm" route, which points at the skill this graft replaced.
if [ -d "$TARGET/.agents/skills" ]; then
  copy skills/shared/trellis-continue/SKILL.md .agents/skills/trellis-continue/SKILL.md
fi

# Upstream bug, still live in 0.6.14: ai-tools.js sets cliFlag "claude" for Claude
# Code, so a fresh `trellis init --claude` writes `--platform claude` into
# /trellis:continue. The parser only matches "claude-code" / "Claude Code", so every
# platform-scoped step body is silently dropped — `--mode phase --step 2.2` returns
# 4 lines instead of 18. This copy carries the corrected value.
copy commands/claude/trellis/continue.md .claude/commands/trellis/continue.md

# ------------------------------------------------- superseded skills, gated --
# Trellis ships a `trellis-brainstorm` skill and a `trellis-check` skill; this graft
# replaced what both do. Their descriptions still match the triggers they always
# matched, so the main session can auto-load one and land back on the workflow this
# graft replaced. `trellis-check` is the worse case: it is the exact name of the
# read-only sub-agent Phase 2.2 dispatches, and the skill self-fixes.
#
# Until now the only guard was a line in the AGENTS.md section telling the model to
# ignore them — prose against a skill whose description matches the trigger better
# than the prose does. `disable-model-invocation: true` is the Claude Code mechanism
# built for this: the description stops being loaded into context at all, so the
# model cannot reach the skill, while `/trellis-brainstorm` still works by hand.
#
# Editing the deployed file is what Trellis's own trellis-meta docs call the
# supported override pattern: the hash diverges from .template-hashes.json and
# `trellis update` then leaves the file alone. `trellis update -s` above makes that
# skip automatic rather than an interactive keep/overwrite prompt. Two caveats from
# those same docs — the override is per-platform (hence the glob over every platform
# skill root), and `trellis update --force` would overwrite it (re-run this script).

info "gating superseded Trellis skills"
if [ "$DRY_RUN" = 1 ]; then
  printf '  %s[dry-run] add disable-model-invocation to trellis-brainstorm / trellis-check SKILL.md in every platform skill root%s\n' "$DIM" "$RST"
else
  python3 - "$TARGET" trellis-brainstorm trellis-check <<'PY' | while IFS= read -r line; do ok "$line"; done
import pathlib, sys

target, names = pathlib.Path(sys.argv[1]), sys.argv[2:]
FLAG = "disable-model-invocation: true"
lines = []

for name in names:
    # Platform skill roots are all one hidden directory deep: .claude/skills/,
    # .agents/skills/, .codex/skills/, .reasonix/skills/, .kimi-code/skills/, …
    for skill in sorted(target.glob(f".*/skills/{name}/SKILL.md")):
        rel = skill.relative_to(target)
        text = skill.read_text(encoding="utf-8")
        if not text.startswith("---\n"):
            lines.append(f"{rel} has no frontmatter — left alone")
            continue
        end = text.find("\n---", 3)          # newline before the closing fence
        if end == -1:
            lines.append(f"{rel} frontmatter is unterminated — left alone")
            continue
        if "disable-model-invocation" in text[:end]:
            lines.append(f"{rel} already gated")
            continue
        skill.write_text(text[:end] + "\n" + FLAG + text[end:], encoding="utf-8")
        lines.append(f"{rel} gated")

print("\n".join(lines) if lines else "no superseded skills present — nothing to gate")
PY
fi

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

# One -a per agent. `-a claude-code,codex` is rejected outright ("Invalid agents"),
# unlike -s where a comma-separated list degrades silently into a listing. Only name
# the platforms this repo actually has, so a Claude-only repo doesn't grow a stray
# ~/.agents/skills/ tree.
SKILL_AGENTS="-a claude-code"
CODEX_NOTE=""
if [ -d "$TARGET/.codex" ] || [ -d "$TARGET/.agents/skills" ]; then
  SKILL_AGENTS="$SKILL_AGENTS -a codex"
  CODEX_NOTE="
     This repo has Codex configured, so the command installs to both
     ~/.claude/skills/ (Claude Code) and ~/.agents/skills/ (Codex)."
fi

cat <<EOF

${GRN}Done.${RST} trellis-graft $GRAFT_VERSION installed into $TARGET

Two things this script deliberately does NOT do — finish them by hand:

  1. Install the engineering skills (once per machine, shared by every repo):

     npx skills@latest add mattpocock/skills -g --copy -y $SKILL_AGENTS \\
       -s grill-with-docs -s grilling -s domain-modeling -s to-spec -s to-tickets \\
       -s tdd -s implement -s code-review -s research -s diagnosing-bugs \\
       -s codebase-design -s prototype

     Repeat -s per skill and -a per agent; a comma-separated -s list silently falls
     through to a listing, and a comma-separated -a list is rejected outright.
     Use -a claude-code, not -a claude, or it installs into ~20 agent directories.$CODEX_NOTE

  2. Start a NEW session in $TARGET. Agent and skill definitions are cached at
     session start, so the ones installed just now do not take effect until then.
EOF
