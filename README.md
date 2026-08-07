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

## 平台支持

`workflow.md` 本身是**完全平台无关**的——它内建 18 个平台的路由块，
Trellis 的解析器对平台名做模糊匹配（转小写、去 `-`/`_`/空格）。实测：

```
--platform codex     -> 正常     --platform cursor    -> 正常
--platform gemini    -> 正常     --platform opencode  -> 正常
--platform claude    -> 正文被丢  --platform claude-code -> 正常
```

所以**官方通道对任何平台都直接可用**：

```bash
trellis init --codex --workflow trellis-mattpocock \
  --workflow-source gh:Episkey-G/trellis-graft
```

`install.sh` 装的 8 项里，平台相关性是这样：

| 产物 | 平台 |
| --- | --- |
| `.trellis/agents/{check,implement}.md` | 通用（channel runtime 的 platform-agnostic role card） |
| `docs/agents/*.md`、`AGENTS.md` 段落 | 通用 |
| `.claude/agents/trellis-*.md` | **仅 Claude Code**。Trellis 为 14 个平台各出一套；Codex 例外，它用 `.codex/agents/*.toml` |
| `.claude/commands/trellis/continue.md` | **仅 Claude Code 需要**（见文末的上游 bug 一节；其他平台的 cliFlag 与块名模糊匹配后相等，不受影响） |

**当前 `install.sh` 只支持 Claude Code**——复制路径写死在 `.claude/` 下。
其他平台可以先用官方通道拿到 workflow.md，那已经是这套东西的主体；
sub-agent 定义要么沿用 Trellis 自带的，要么手动照着 `agents/claude/` 的内容改写成
目标平台的格式。

---

## 怎么调用它 —— 不用复制到项目里

`install.sh` 从来不需要复制进目标仓库，`--target` 指哪打哪。三条路，按你手上有没有
checkout 选：

### 一、直接调 checkout 里的脚本

```bash
/path/to/trellis-graft/install.sh --target /path/to/your-repo
```

### 二、软链到 PATH（推荐日常用，一次设置）

在 trellis-graft checkout 里执行一次：

```bash
ln -s "$PWD/install.sh" ~/.local/bin/trellis-graft
```

之后在任何仓库里就是一个词，`--target` 缺省为当前目录：

```bash
cd ~/some-project && trellis-graft
```

脚本会先解开符号链接找到真正的 checkout，所以装的是**你本地这一份**，不走网络，
本地没推的改动也照样生效。

### 三、`curl | bash`（新机器、CI，本地没 clone 过）

```bash
curl -fsSL https://raw.githubusercontent.com/Episkey-G/trellis-graft/main/install.sh \
  | bash -s -- --target .
```

这条路没有本地 checkout，脚本自己浅克隆一份到临时目录，跑完删掉。
`--ref` 只在这条路上有意义，用来钉版本：

```bash
curl -fsSL https://raw.githubusercontent.com/Episkey-G/trellis-graft/main/install.sh \
  | bash -s -- --target . --ref v1.0.0
```

三条路的硬要求都一样：`trellis`、`git`、`python3` 在 PATH 上。

目标**不必**是 git 仓库——Trellis 自己就不要求，`trellis init` 在纯目录里能跑，这个脚本也
只是复制文件。不是仓库时它警告一句然后继续。但要知道后果：Phase 2.2 的 `trellis-check`
要 `git diff <fixed-point>...HEAD`，Phase 3.4 是提交，这两步在非仓库里是死的。想用完整流程
就先 `git init`。

下文的命令一律写成软链后的 `trellis-graft`，换成前两种写法等价。

---

## 场景一：仓库还没装过 Trellis

一条命令搞定，`install.sh` 发现 `.trellis/` 不存在时会自己调 `trellis init`：

```bash
cd /path/to/your-repo && trellis-graft
```

平台默认 `claude`，换平台用 `--platform`：

```bash
trellis-graft --platform cursor
```

它内部执行的是：

```bash
trellis init -y --claude \
  --workflow trellis-mattpocock \
  --workflow-source gh:Episkey-G/trellis-graft
# 然后复制 8 个文件 + 注入 AGENTS.md 段落
```

`-y` 不是可有可无的：不加它 `trellis init` 会弹交互提示（statusLine 等），
在任何没有 TTY 的地方直接 `ERR_USE_AFTER_CLOSE` 崩掉。

**只想要 workflow.md、不要 agent 定义**，那就只跑官方那一条：

```bash
trellis init --claude --workflow trellis-mattpocock \
  --workflow-source gh:Episkey-G/trellis-graft
```

想让每个新仓库都自动带上，在 `~/.zshrc` 里包一层：

```bash
tinit() {
  trellis init --claude \
    --workflow trellis-mattpocock \
    --workflow-source gh:Episkey-G/trellis-graft "$@"
}
```

---

## 场景二 / 三：仓库已装 Trellis —— 接入，或升级

**场景二**（已装原版 Trellis，要接入这套）和 **场景三**（已装这套，要升级到新版）
**是同一条命令**。脚本看 `AGENTS.md` 里有没有 `MATTPOCOCK-GRAFT` marker 判断是哪种，
但两者的动作完全一样：

```bash
cd /path/to/your-repo && trellis-graft
```

### 它内部到底跑了什么

```bash
# 1. 先把 Trellis 自身升到当前 CLI 版本
trellis update -s

# 2. 再换 workflow.md
trellis workflow -m gh:Episkey-G/trellis-graft -t trellis-mattpocock -f

# 3. 最后复制 8 个文件 + 注入 AGENTS.md 段落
```

**为什么是 `-s`**：`-s` = skip all modified。装了这套 graft 的仓库里，被 `trellis update`
判为 "Modified by you" 的恰好就是我们改过的那几个文件。跳过它们、只更新
scripts / hooks，正是我们要的——而且非交互，所以能写进脚本。

**为什么是 `-f`**：`workflow.md` 必然是 modified 状态，不加 `-f` 会停下来问。
升级的本意就是覆盖它，所以强制。

**为什么这个顺序不能反**：`.trellis/scripts/` 下的 hook 就是读 workflow.md 的解析器。
必须先让解析器到新版，再让新语法的 workflow.md 落地。反过来会出现新语法配旧解析器，
症状是断点或 phase 正文静默变空。

**Trellis 版本太旧怎么办**：不用管，第 1 步的 `trellis update` 会把它拉到当前 CLI 版本。
先升级全局 CLI 即可：`npm i -g @mindfoldhq/trellis@latest`。

### 先看看会改什么

```bash
trellis-graft --dry-run
```

列出将执行的命令和将写入的路径，不落盘。

### 装了哪些文件

平台无关的 5 个，任何目标仓库都装：

| 落点 | 是什么 |
| --- | --- |
| `.trellis/agents/implement.md` | channel runtime 版，同样 red-green-refactor |
| `.trellis/agents/check.md` | channel runtime 版，去掉自我修复，改为只报告 |
| `docs/agents/issue-tracker.md` | 把技能说的 "issue tracker" 映射到 `.trellis/tasks/` |
| `docs/agents/domain.md` | 划清 `CONTEXT.md` / `docs/adr/` 与 `.trellis/spec/` 的分工 |
| `.trellis/workflow.md` | 由官方 `trellis workflow` 从 marketplace 换入，不是本脚本写的 |

Claude Code 的 4 个：

| 落点 | 是什么 |
| --- | --- |
| `.claude/agents/trellis-implement.md` | 驱动 `tdd`；`tools` 加了 `Skill`（上游没有，导致它调不动技能） |
| `.claude/agents/trellis-check.md` | 单轴只读评审，从 dispatch prompt 读 `Axis:`；带 Fowler 坏味道基线 |
| `.claude/agents/trellis-research.md` | 加载 `research`，只回文件路径和一行摘要，不回正文 |
| `.claude/commands/trellis/continue.md` | 修 `--platform` 值（见下），并把 1.1 路由改到 `/grill-with-docs` |

Codex 的 4 个，**仅当目标仓库有 `.codex/agents/`**（即 `trellis init` 配过 Codex）才装：

| 落点 | 是什么 |
| --- | --- |
| `.codex/agents/trellis-implement.toml` | 同 Claude 版：驱动 `tdd`，按 vertical slice 走，禁止 commit |
| `.codex/agents/trellis-check.toml` | 单轴只读评审。`sandbox_mode = "read-only"`——上游是 `workspace-write` 且会自我修复 |
| `.codex/agents/trellis-research.toml` | 外部调研走 `research` 技能的 primary-source 纪律 |
| `.agents/skills/trellis-continue/SKILL.md` | Codex 走的 continue 入口，同样把 1.1 路由改到 `/grill-with-docs` |

Codex 的 check 值得单说：Claude 版靠 frontmatter 的 `tools:` 白名单挡住写操作，Codex 版是
`sandbox_mode = "read-only"`——**沙箱级强制**，比"提示词请求它别改"硬。代价是 lint 若要写
缓存（`.tsbuildinfo`、eslint cache）会失败，所以 agent 定义里写明了这种失败要报成
"not runnable under read-only"，不能当成代码有问题。

外加 `AGENTS.md` 里一段用 marker 包裹的说明，位置在 `<!-- TRELLIS -->` 托管块**之外**，
所以 `trellis update` 会把 AGENTS.md 判为 unchanged，不会来打扰。

### 还会关掉两个被换掉的 Trellis 技能

`trellis-brainstorm` 和 `trellis-check`（**技能**，不是同名的那个子代理）被这个 graft
换掉了，但它们的 description 还留在原地：一个的触发词是"需求不清楚、或用户描述了一个新
功能"，一个是"代码写完需要质检、提交之前"——正好是 Phase 1.1 和 Phase 2.2 的入口。
更糟的是 `grill-with-docs` 带 `disable-model-invocation`、模型根本看不见，所以这场触发
词竞争是单方面的。以前唯一的拦阻是 AGENTS.md 里一句"别加载它"，拿散文去跟一个描述匹配
得更准的技能抢。

现在 `install.sh` 往这两个技能的 `SKILL.md` frontmatter 各加一行：

```yaml
disable-model-invocation: true
```

description 从此不进上下文，模型看不到、也调不动；你仍然可以手敲 `/trellis-brainstorm`
和 `/trellis-check`。每个平台的 skill root 都会改（`.claude/skills/`、`.agents/skills/`
……），因为这个覆盖是按平台生效的。重复跑幂等，已经加过就跳过。

这正是 Trellis 官方 `trellis-meta` 文档里写的 override 方式：改本地文件 → hash 与
`.template-hashes.json` 分叉 → `trellis update` 认出这是用户改动就不再碰它。install.sh
跑的 `trellis update -s` 让这个跳过自动发生，不会弹 keep / overwrite 询问。唯一会覆盖它
的是 `trellis update --force`，之后重跑 `trellis-graft` 补回来即可。

### 跑完还要手动做两件事

**1. 装技能**（每台机器一次，14 个仓库共享）：

```bash
npx skills@latest add mattpocock/skills -g --copy -y -a claude-code -a codex \
  -s grill-with-docs -s grilling -s domain-modeling -s to-spec -s to-tickets \
  -s tdd -s implement -s code-review -s research -s diagnosing-bugs \
  -s codebase-design -s prototype
```

`-s` 和 `-a` 都必须每项重复一次。`-s` 用逗号分隔会静默退化成列出清单；`-a` 用逗号分隔
直接报 `Invalid agents` 拒绝执行。`-a claude-code` 不能写成 `-a claude`，否则会往约 20 个
agent 目录里各装一份。

落点：`-a claude-code` → `~/.claude/skills/`，`-a codex` → `~/.agents/skills/`。只用 Claude
就把 `-a codex` 去掉——`install.sh` 跑完打印的那条命令会按目标仓库实际配了哪些平台自动带上。

**2. 开新会话。** agent 和 skill 定义在会话启动时缓存，刚装的这些在当前会话里不生效。

### 验证装对了

```bash
# 平台块正文没被丢：应该是十几行，不是 4 行
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform claude-code

# 两个被换掉的技能已关掉：每个平台 skill root 各输出一行
grep -l 'disable-model-invocation' .*/skills/trellis-brainstorm/SKILL.md .*/skills/trellis-check/SKILL.md

# 新会话里 agent 列表应显示 trellis-check (Tools: Read, Bash, Glob, Grep)
```

---

## 场景四：Trellis 官方发新版了，这个仓库怎么跟

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

从第 4 步接着跑。冲突没解干净就 `--continue` 会被拒绝。

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

### 升完之后

各消费仓库再跑一次场景二/三那条命令即可：

```bash
cd /path/to/your-repo && trellis-graft
```

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
install.sh                          目标仓库侧唯一命令（接入 = 升级，从任意位置调用）
upgrade.sh                          本仓库侧唯一命令（跟进上游）
CLAUDE.md                           跟进上游的操作规程，供 Claude Code 会话启动时加载
```

---

## 许可证

AGPL-3.0-only。`workflows/` 与 `agents/` 下的文件改编自 Trellis，`upstream/` 是它的
逐字节副本，因此本仓库沿用同一许可证。归属详见 [NOTICE](NOTICE)。

mattpocock/skills 不在本仓库分发范围内，遵循其自身许可证。
