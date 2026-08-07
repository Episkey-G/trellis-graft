# CLAUDE.md — trellis-graft

这个仓库不是应用代码，是**一套模板加两个 shell 脚本**：把 Trellis 的工作流骨架和
mattpocock/skills 的工程技能层嫁接起来。所以日常只有两类工作 —— 跟进上游，和装到消费仓库。

背景、设计取舍、装了哪 8 个文件、修了哪个上游 bug，都在 [README.md](README.md)。
这份文件只写**怎么操作**。

---

## 两层模型，先分清用户说的是哪一层

| 层 | 命令 | 在哪跑 | 做什么 |
| --- | --- | --- | --- |
| graft 跟上游 Trellis | `./upgrade.sh` | **本仓库** | 三方合并上游新版模板，刷新 `upstream/` 基线，递增 `VERSION` |
| 消费仓库跟 graft | `trellis-graft` | **目标仓库** | `trellis update -s` → 换 workflow.md → 复制 8 个产物 |

「上游 Trellis 发新版了，帮我更新」= 第一层。下面整节讲的都是它。

---

## 升级流程（用户说「帮我更新 Trellis」时执行）

### 0. 前置检查，一步都别省

```bash
git -C . status --short && git -C . branch --show-current
```

**working tree 必须干净。** `upgrade.sh` 第 3 步用 `git merge-file` **原地改工作区文件**
（[upgrade.sh:134](upgrade.sh:134)），脏树会让 `git diff` 分不清哪些是合并结果、哪些是你原本的改动，
也没法干净回退。不干净就停下来问用户怎么处理，不要自己 stash。

### 1. 跑它，就一条命令

```bash
./upgrade.sh
```

**不要先手动 `npm i -g @mindfoldhq/trellis@latest`。** 那是 [upgrade.sh:98](upgrade.sh:98) 的 step 1，
脚本自己会升全局 CLI。手动升 CLI 却不跑 upgrade.sh，会让消费仓库拿到「新 parser + 旧基线 workflow.md」。

钉版本用 `./upgrade.sh 0.7.0-beta.3`。

### 2. 三种结局，分别怎么接

**A. `Already current`** —— `upstream/VERSION` 已等于新 CLI 版本，[upgrade.sh:103](upgrade.sh:103) 早退 exit 0。
如实告诉用户已是最新，不要再做任何事。重复跑无害。

**B. 五步跑完** —— 直接跳到第 3 节验证。

**C. 停在 step 3，报冲突** —— 状态写进 `.upgrade-state`（已 gitignore），exit 1。按下面解。

### 冲突怎么解

冲突块是 `--diff3` 三段格式：`ours` / `base` / `upstream`。原则是
**保住 graft 的改造意图，吸收上游的结构性变化**。

**冲突落点是重要信号**：正常情况下冲突只出现在被改写过的 step 正文里
（`#### 1.2` / `#### 2.1` / `#### 2.2` 这几段）。
如果冲突出现在 `## Phase Index`、`[workflow-state:*]` 块或平台标记里，**那不正常** ——
停下来告诉用户，不要自作主张合掉，那通常意味着上游动了解析契约。

解完之后：

```bash
./upgrade.sh --continue
```

从 step 4 接着跑。冲突标记没清干净会被 [upgrade.sh:89](upgrade.sh:89) 拒绝。

**要中止整次升级**（没有 `--abort` 这个选项，手动来）：

```bash
git checkout -- workflows/ agents/ commands/ && rm -f .upgrade-state
```

**`--continue` 报 "the fetched templates are gone"**：`/tmp` 里的模板被系统清掉了，
重跑 `./upgrade.sh`（不带 `--continue`），前面的冲突解决结果还在工作区，不会白做。

### 3. 验证

step 4 自动校验 5 个解析器敏感结构（`## Phase Index`、`## Phase 1: Plan`、
`[workflow-state:*]` 配对、平台标记配对、`#### X.Y` step 存在），过不了会 exit 1。

**这只是结构校验，不是端到端。** 真正的验证要在一个装了这套 graft 的真实仓库里跑：

```bash
python3 ./.trellis/scripts/get_context.py --mode phase --step 2.2 --platform claude-code
```

应该是十几行正文，**不是 4 行**。4 行意味着平台块正文被丢了。

另外自己看一遍 `git diff`：合并结果对不对，是模型该判断的，不能只依赖脚本退出码。

### 4. 收尾

`upgrade.sh` 打印 git 命令但**不代跑**，这是 [upgrade.sh:17](upgrade.sh:17) 的有意设计 ——
发布是用户的决定。**不要自动 commit / tag / push**，把命令给用户，等他说了再动。

---

## 红线

- **不要手改 `upstream/`。** 那是上游模板的逐字节副本，三方合并的 BASE。手改一次，
  以后每次升级的 diff 都是错的。它只能由 `upgrade.sh` step 5 刷新。
- **不要手改 `VERSION`。** 由 [upgrade.sh:228](upgrade.sh:228) 按 minor+1 递增。
  它会被 `install.sh` 写进目标仓库 AGENTS.md 的 marker，手动改会让 marker 和实际内容对不上。
  改安装器本身（`install.sh`）不算内容变更，不该 bump。
- **不要给 `upgrade.sh` 做符号链接。** 它 [upgrade.sh:23-24](upgrade.sh:23) 拿到 `HERE` 后立刻
  `cd` 过去，而那个 `HERE` 没解符号链接。走软链会 `cd` 进 `~/.local/bin`，然后在读
  `upstream/VERSION` 时以一句莫名其妙的 "No such file" 挂掉。它本来就该在 checkout 里跑。
  （`install.sh` 不同，它已经解符号链接，随便软链。）
- **改完 shell 脚本要验证。** `bash -n` 加 `shellcheck -S warning`，再用临时 git 仓库
  跑 `--dry-run` 走一遍真实路径。这两个脚本没有测试套件，dry-run 就是测试。

---

## 装到消费仓库

一条命令，**接入和升级不分**（脚本看 AGENTS.md 里的 `MATTPOCOCK-GRAFT` marker 自己判断）：

```bash
cd ~/some-project && trellis-graft
```

`trellis-graft` 是 `~/.local/bin/` 里指向本仓库 `install.sh` 的符号链接。没设过就是：

```bash
ln -s "$PWD/install.sh" ~/.local/bin/trellis-graft
```

三种调用方式（checkout 直调 / PATH 软链 / `curl | bash`）见 [README.md](README.md) 的
「怎么调用它」一节。`--target` 缺省为当前目录，`--dry-run` 只打印不落盘。

**跑完必须提醒用户两件事**，脚本结尾也会印：装 mattpocock 技能（每台机器一次），
以及**开新会话**（agent 和 skill 定义在会话启动时缓存）。

---

## 文件地图

| 路径 | 性质 |
| --- | --- |
| `upstream/` | **生成物**，上游模板逐字节副本，合并的 BASE，只由 upgrade.sh 写 |
| `VERSION` | **生成物**，由 upgrade.sh 递增 |
| `workflows/`、`agents/`、`commands/`、`skills/`、`docs/`、`snippets/` | 手写的改造产物，冲突就发生在这里 |
| `install.sh` | 消费仓库侧唯一命令，可从任意位置调用 |
| `upgrade.sh` | 本仓库侧唯一命令，必须在 checkout 里跑 |
| `index.json` | marketplace 索引，`--workflow-source` 读它 |
| `.upgrade-state` | 冲突时的断点，gitignore，`--continue` 读它 |

`agents/` 按平台分目录：`claude/`（.md）、`codex/`（.toml）、`channel/`（平台无关的
channel runtime）。`skills/shared/` 是 `.agents/skills/` 共享层的产物，Codex 读它。

`upgrade.sh` 的作用面写死在 [upgrade.sh:65-77](upgrade.sh:65) 的 `FILES` 数组里，11 个文件。
新增一个需要跟上游同步的产物时，要同时加进这个数组，否则它会静默漏掉。

两个 continue 条目**共享同一个上游源** `common/commands/continue.md`——上游只有一份，
各平台 configurator 渲染出不同格式。它们靠 [upgrade.sh:83](upgrade.sh:83) 的 `cli_flag_for`
分别把 `{{CLI_FLAG}}` 替换成 `claude-code` / `codex`；替换错会让 `--platform` 那行每次升级
都冲突。新增走同一模板的平台时，要同时加 `FILES` 条目和 `cli_flag_for` 分支。
