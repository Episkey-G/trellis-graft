# trellis-graft

[Trellis](https://github.com/mindfold-ai/Trellis) 的工作流骨架，配上
[mattpocock/skills](https://github.com/mattpocock/skills) 的工程技能层。

Trellis 保留三阶段状态机、任务树、per-turn 断点注入、spec 注入和提交闸门；
每个 phase 内部"具体做什么"换成 mattpocock 的技能：

| Phase | 原本 | 换成 |
| --- | --- | --- |
| 1.1 需求探索 | `trellis-brainstorm` | `grill-with-docs` → `to-spec` → `to-tickets` |
| 1.2 研究 | 主会话直接读 | `trellis-research` 子代理（内部驱动 `research`） |
| 2.1 实现 | `trellis-implement` 直接写 | `trellis-implement` 子代理驱动 `tdd`，逐个行为切片 red-green-refactor |
| 2.2 质量检查 | `trellis-check` 单体检查，会自我修复 | `trellis-check` 子代理 **双轴并行、只读**（`Axis: standards` / `Axis: spec`） |
| 3.2 调试复盘 | `trellis-break-loop` | `diagnosing-bugs`（`trellis-break-loop` 保留为 fallback） |
| 3.3 spec 更新 | `trellis-update-spec` | 不变，另加 `domain-modeling` 维护 `CONTEXT.md` / ADR |

**技能本身不在这个仓库里。** 它们仍从 mattpocock 上游安装，跟着上游更新。
这里只有 Trellis 侧的改造：workflow 模板、agent 定义、以及把两套词汇接起来的说明文档。

需要 Trellis **0.6.14 或更高**。

---

## 一、全新仓库怎么接

```bash
trellis init --claude \
  --workflow trellis-mattpocock \
  --workflow-source gh:Episkey-G/trellis-graft
```

这一步只装 workflow.md。agent 定义、`/trellis:continue` 修复和说明文档还要跑一次：

```bash
/path/to/trellis-graft/install.sh --target .
```

嫌两条麻烦就只跑第二条——`install.sh` 发现 `.trellis/` 不存在时会自己调
`trellis init`（平台默认 `claude`，用 `--platform` 改）。

想让 `trellis init` 每次都带上这套，在 `~/.zshrc` 里包一层：

```bash
tinit() {
  trellis init --claude \
    --workflow trellis-mattpocock \
    --workflow-source gh:Episkey-G/trellis-graft "$@"
}
```

---

## 二、已有仓库怎么接、怎么升级

**这两件事是同一条命令。**

```bash
/path/to/trellis-graft/install.sh --target /path/to/your-repo
```

脚本自己判断是首次接入还是后续升级（看 `AGENTS.md` 里有没有 `MATTPOCOCK-GRAFT` marker），
两种情况的动作完全一样。

### 它内部到底跑了什么

```bash
# 1. 先把 Trellis 自身升到当前 CLI 版本
trellis update -s

# 2. 再换 workflow.md
trellis workflow -m gh:Episkey-G/trellis-graft -t trellis-mattpocock -f

# 3. 最后复制 8 个文件 + 注入 AGENTS.md 段落
```

**为什么是 `-s`**：`-s` = skip all modified。装了这套 graft 的仓库里，被 `trellis update`
判为 "Modified by you" 的恰好就是我们改过的那 8 个文件。跳过它们、只更新
scripts / hooks，正是我们要的——而且非交互，所以能写进脚本。

**为什么是 `-f`**：`workflow.md` 必然是 modified 状态，不加 `-f` 会停下来问。
升级的本意就是覆盖它，所以强制。

**为什么这个顺序不能反**：`.trellis/scripts/` 下的 hook 就是读 workflow.md 的解析器。
必须先让解析器到新版，再让新语法的 workflow.md 落地。反过来会出现新语法配旧解析器，
症状是断点或 phase 正文静默变空。

### 装了哪 8 个文件

| 落点 | 是什么 |
| --- | --- |
| `.claude/agents/trellis-implement.md` | 驱动 `tdd`；`tools` 加了 `Skill`（上游没有，导致它调不动技能） |
| `.claude/agents/trellis-check.md` | 单轴只读评审，从 dispatch prompt 读 `Axis:`；带 Fowler 坏味道基线 |
| `.claude/agents/trellis-research.md` | 加载 `research`，只回文件路径和一行摘要，不回正文 |
| `.trellis/agents/implement.md` | channel runtime 版，同样 red-green-refactor |
| `.trellis/agents/check.md` | channel runtime 版，去掉自我修复，改为只报告 |
| `.claude/commands/trellis/continue.md` | 修 `--platform` 值（见下） |
| `docs/agents/issue-tracker.md` | 把技能说的 "issue tracker" 映射到 `.trellis/tasks/` |
| `docs/agents/domain.md` | 划清 `CONTEXT.md` / `docs/adr/` 与 `.trellis/spec/` 的分工 |

外加 `AGENTS.md` 里一段用 marker 包裹的说明，位置在 `<!-- TRELLIS -->` 托管块**之外**，
所以 `trellis update` 会把 AGENTS.md 判为 unchanged，不会来打扰。

### 跑完还要手动做两件事

**1. 装技能**（每台机器一次，14 个仓库共享）：

```bash
npx skills@latest add mattpocock/skills -g --copy -y -a claude-code \
  -s grill-with-docs -s grilling -s domain-modeling -s to-spec -s to-tickets \
  -s tdd -s implement -s code-review -s research -s diagnosing-bugs \
  -s codebase-design -s prototype
```

`-s` 必须每个技能重复一次，逗号分隔会静默退化成列出清单。
`-a claude-code` 不能写成 `-a claude`，否则会往约 20 个 agent 目录里各装一份。

**2. 开新会话。** agent 和 skill 定义在会话启动时缓存，刚装的这些在当前会话里不生效。

### 验证装对了

```bash
# 平台块正文没被丢：应该是十几行，不是 4 行
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform claude-code

# 新会话里 agent 列表应显示 trellis-check (Tools: Read, Bash, Glob, Grep)
```

---

## 三、Trellis 官方发新版了怎么办

```bash
cd /path/to/trellis-graft
./upgrade.sh                  # 跟到 npm latest
./upgrade.sh 0.7.0-beta.3     # 或指定版本
```

一条命令跑完五步：升级全局 CLI → `npm pack` 取新版原版模板 → 逐文件三方合并 →
校验解析契约 → 刷新 `upstream/` 基线并递增版本号。git 提交和推送它只打印命令、不代劳。

### 三方合并是怎么回事

`upstream/` 里存着 graft 所基于的上游原版，也就是合并的 BASE：

```
BASE   = upstream/<file>           graft 当初基于的上游原版
OURS   = <file>                    本仓库改造后的版本
THEIRS = 新版 npm 包里的同一文件      上游的新原版
```

所以每次升级是"把上游这一版的改动合进我的改造"，而不是"凭记忆重做一遍嫁接"。

### 有冲突怎么办

脚本停在第 3 步并列出冲突文件，冲突块是 `--diff3` 格式（ours / base / upstream 三段）。
解完之后：

```bash
./upgrade.sh --continue
```

从第 4 步接着跑。

**冲突只会出现在你改过的地方。** 实测把上游 0.6.7→0.6.14 那 39 行变更压到这套 graft 上，
产生 4 个冲突，全部落在改写过的 `#### 1.2` / `#### 2.1` / `#### 2.2` 三个 step 正文内；
`## Phase Index`、6 对 `[workflow-state:*]` 块、平台标记全部零冲突。
**如果冲突出现在结构区，多看两眼，那不正常。**

### 实测的上游改动频率

| 文件 | 0.6.7→0.6.14 | 0.6.10→0.6.14 | 0.6.12→0.6.14 |
| --- | --- | --- | --- |
| `trellis/workflow.md` | 39 行 | 0 | 0 |
| 其余 6 个 | 0 | 0 | 0 |

跨 7 个版本、约 3.5 周，只有 workflow.md 动过一次。多数版本升级是零冲突的，
`trellis update` 只更新 scripts / hooks，而那些本来就自动覆盖。

---

## 我们修掉的上游 bug

`dist/types/ai-tools.js` 里 Claude Code 的 `cliFlag` 是 `"claude"`，于是
`trellis init --claude` 生成的 `/trellis:continue` 里写的是 `--platform claude`。
但解析器只认 `claude-code` / `Claude Code`，结果**每个平台限定的 step 正文都被静默丢弃**：

```bash
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform claude
#  -> 4 行（正文没了）
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform claude-code
#  -> 18 行（正常）
```

截至 0.6.14 上游未修。本仓库分发的 `continue.md` 带的是修正值。

---

## 仓库结构

```
index.json                          官方 marketplace 索引，供 --workflow-source 读取
VERSION                             graft 版本号，install.sh 写进 AGENTS.md marker
upstream/                           三方合并的 BASE —— Trellis 原版逐字节副本
  VERSION                             对应的 Trellis 版本
workflows/trellis-mattpocock/       ← 官方通道读这里
agents/claude/                      → 目标仓库 .claude/agents/
agents/channel/                     → 目标仓库 .trellis/agents/
commands/claude/trellis/            → 目标仓库 .claude/commands/trellis/
docs/agents/                        → 目标仓库 docs/agents/
snippets/agents-md-section.md       → 注入目标仓库 AGENTS.md
install.sh                          目标仓库侧唯一命令（接入 = 升级）
upgrade.sh                          本仓库侧唯一命令（跟进上游）
```

---

## 许可证

AGPL-3.0-only。`workflows/` 与 `agents/` 下的文件改编自 Trellis，`upstream/` 是它的
逐字节副本，因此本仓库沿用同一许可证。归属详见 [NOTICE](NOTICE)。

mattpocock/skills 不在本仓库分发范围内，遵循其自身许可证。
