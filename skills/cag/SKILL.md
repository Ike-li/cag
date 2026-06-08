---
name: cag
description: Autonomous code execution via codex/agy. Use when user asks to "implement", "refactor", "fix", "update code/docs". Auto-selects isolation mode. Codex/agy execute, Claude verifies and merges. Handles parallel tasks and worktree isolation.
argument-hint: "[codex|agy] <task>"
---

# CAG — Claude Autonomous codex/agy orchestrator

**codex/agy 直接执行改动，Claude 验证并合并。**

自动选择模式：
- **direct mode** — 单一小改动，provider 直接编辑工作树，Claude 审查 git diff + 跑测试
- **worktree mode** — 多任务并行/有风险，每个子任务在独立 worktree 隔离执行，Claude 验证后合并

## Usage

```
/cag <task>                 # 自动选模式
/cag codex <task>           # 强制用 codex（逻辑/重构/安全/测试）
/cag agy <task>             # 强制用 agy（文档/大上下文/UI/UX）
/cag --dry-run <task>       # Dry-run：provider 运行，只看 diff，不 commit
```

---

## Mode selection (automatic)

**当满足以下任一条件时，自动切换到 worktree mode：**
- 任务可拆分为 2+ 个文件不相交的子任务（可并行）
- 任务涉及多个模块/组件（需隔离验证）
- 任务有回滚风险（需要分支隔离）

**否则用 direct mode**（单文件、小改动、低风险）。

---

## Direct Mode — 轻量单任务执行

provider 直接编辑当前工作树，Claude 审查 git diff 并跑测试验证。

### Preconditions

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "not a git repo — diff review unavailable"
git status --porcelain   # 记录执行前的状态
which codex agy
```

### Step 1 — Run executor (direct provider invocation)

Direct mode calls the provider directly (no cag-exec, since we're working in main repo).

**For codex:**
```bash
PROMPT=$(cat <<'EXEC_PROMPT'
<task + acceptance criteria + "edit files directly">
EXEC_PROMPT
)

# Direct mode has NO jailbreak sentinel (it intentionally edits the main repo),
# so the provider sandbox is the primary guard. -s workspace-write locks codex's
# writable root to $PWD (the main repo) and refuses writes outside it; still
# non-interactive, no approval prompt. (Was --dangerously-bypass-approvals-and-sandbox.)
RAW="/tmp/cag-direct-codex-$$.txt"
env -u CLAUDECODE -u CLAUDE_SESSION_ID -u CLAUDECODE_SESSION_ID \
    -u CLAUDE_CODE_ENTRYPOINT -u RUST_LOG -u RUST_BACKTRACE -u RUST_LIB_BACKTRACE \
    codex exec -s workspace-write -C "$PWD" - > "$RAW" 2>&1 <<< "$PROMPT" || RC=$?
RC=${RC:-0}
cat "$RAW"
```

**For agy:**
```bash
PROMPT=$(cat <<'EXEC_PROMPT'
<task + acceptance criteria + "edit files directly">
EXEC_PROMPT
)

# Direct mode has NO jailbreak sentinel, so agy's sandbox is the primary guard.
# --add-dir "$PWD" pins the workspace to the main repo (agy may otherwise wander
# to ~/.gemini/scratch); --sandbox replaces --dangerously-skip-permissions and is
# what actually keeps agy in place (verified: --add-dir alone does not).
RAW="/tmp/cag-direct-agy-$$.txt"
env -u CLAUDECODE -u CLAUDE_SESSION_ID -u CLAUDECODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT \
    agy --add-dir "$PWD" --sandbox --print "$PROMPT" --print-timeout 9m > "$RAW" 2>&1 || RC=$?
RC=${RC:-0}
cat "$RAW"
```

### Step 2 — VERIFY (main Claude)

```bash
git --no-pager diff            # 审查每一个改动
cd <repo> && <test/build/lint> # 真实验证
```

> **dry-run 模式**：如果用 --dry-run 调用，步骤 1 执行后不 commit；`git --no-pager diff` 展示改动，确认后 `git checkout -- .` 清理，或手动 stage/commit。

决策：
- **pass** → 报告；可选 stage/commit（需先问用户，除非已授权）
- **fail** → 用失败详情重跑 executor（最多 2 轮）
- **错误/不安全改动** → `git checkout -- <files>` 回滚，然后报告

### Step 3 — Report

```
## CAG Direct 结果
执行器: codex / agy
exit_code: <n>
状态: ✓ 通过 / ⚠ 需修 / ✗ 回滚

### 改动（git diff --stat）
<summary>

### 验证（主 Claude 实跑）
- <test 命令>: <结果>

### 下一步
<commit 建议 / 回滚原因 / 待修项>
```

---

## Worktree Mode — 并行隔离执行

每个子任务在独立 worktree 上独立执行，Claude 验证后合并。使用 `codex-delegate` / `agy-delegate` 子 agent。

### Preconditions

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || echo "NOT a git repo — worktree mode requires git"
which codex agy
git status --porcelain | head  # 从干净 base 合并更清晰
```

设置路径：
```bash
BASE=$(git branch --show-current)
REPO=$(basename "$(git rev-parse --show-toplevel)")
RUN=$(date +%Y%m%d-%H%M%S)
ROOT="$HOME/.cache/cag/$REPO/$RUN"
mkdir -p "$ROOT/artifacts"
```

### Step 1 — Plan & decompose (main Claude)

拆分为独立子任务。**关键规则：子任务应该文件不相交**，以便并行分支干净合并。如果两个子任务必须碰同一文件，则在同一 worktree 上顺序执行而非并行。

为每个子任务决定：
- executor: `codex`（逻辑/重构/安全/测试）或 `agy`（文档/大上下文/UI/UX）
- `ACCEPTANCE`: 具体可验证标准
- 如何验证: 实际的 test/build/lint 命令

产生任务图（id, executor, files, acceptance, deps）。

### Step 2 — Create one worktree per subtask

每个子任务 `id`：
```bash
WT="$ROOT/wt/$id"
git worktree add -q "$WT" -b "cag/$id" HEAD
```
（从当前 HEAD 分支，保留你的上下文。）

### Step 3 — Dispatch executors in parallel

在**同一轮**用 `run_in_background: true` 派发所有独立 delegate。在每个 prompt 中传递契约：

```
Agent(
  subagent_type="codex-delegate",       # or "agy-delegate"
  description="codex-delegate: <id>",
  run_in_background=true,
  prompt="""
TASK_ID: <id>
WORKTREE: <abs $WT>
ARTIFACT: <abs $ROOT/artifacts/codex-<id>.md>
SUBTASK:
<what to implement>
ACCEPTANCE:
- <criterion 1>
- <criterion 2>
DRY_RUN: (optional) true — 透传 --dry-run 给 cag-exec；provider 正常运行，跳过 commit，输出 diff
"""
)
```

```bash
DRY_RUN_FLAG=""
[[ "${DRY_RUN:-}" == "true" ]] && DRY_RUN_FLAG="--dry-run"
echo "$PROMPT" | cag-exec $DRY_RUN_FLAG codex "$WORKTREE" "$MODEL_ARG" "$REASONING_ARG"
```

有依赖的子任务：等上游完成，然后派发（可选复用上游 worktree）。

### Step 4 — VERIFY each worktree (main Claude — the whole point)

**不要信任 delegate 自述**。对每个分支：

```bash
# 4-pre. Exit 3 (SANDBOX ESCAPE) 前置处理
# Delegate 遇到哨兵 exit 3 会立即停止并输出 "SENTINEL_TRIGGERED"。
# 主 Claude 需清理主仓库的越狱残留（哨兵只检测+拒commit，不清理文件）。
if grep -q "SENTINEL_TRIGGERED" <delegate output>; then
  echo "⚠️ 哨兵触发：provider 逃出 worktree sandbox"
  MAIN_REPO=$(git -C "$WT" rev-parse --git-common-dir | xargs dirname)
  
  # 清理越狱残留（modified 回滚 + untracked 删除）
  git -C "$MAIN_REPO" checkout -- . 2>/dev/null
  git -C "$MAIN_REPO" clean -fd 2>/dev/null
  
  echo "残留已清理（主仓库恢复 clean）"
  echo "决策：reject（哨兵阻断，不可重试）"
  # 记录到 reject 列表，Step 6 跳过此分支，Final report 上报用户
  continue  # 跳到下一个 worktree
fi

# 4a. 审查真实 diff
git -C "$WT" --no-pager show --stat HEAD
git -C "$WT" --no-pager diff "$BASE"...HEAD

# 4b. 在 worktree 内跑真实验证
cd "$WT" && <test / build / lint command for this subtask>
```

每个 worktree 决策：**accept / fix / reject**。

### Step 5 — Fix loop (max 2–3 rounds)

如果验证失败，向**同一 worktree** 重新派发同一 delegate，在 SUBTASK 后附加失败详情（"previous attempt failed: <stderr/test output>, fix it"）。delegate 添加另一个 commit。重新验证。2–3 轮失败后 → reject 并升级给用户。

### Step 6 — Merge accepted work (main Claude)

从主工作树（在 `$BASE`），逐个合并已接受的分支：
```bash
git merge --no-ff --no-edit "cag/$id"   # 解决/暴露冲突
```

如果合并冲突，停止并报告该分支需要人工解决，而不是强制。

### Step 7 — Cleanup

```bash
for id in <all ids>; do
  git worktree remove --force "$ROOT/wt/$id" 2>/dev/null
  git branch -D "cag/$id" 2>/dev/null
done
# $ROOT/artifacts 下的 artifacts 保留作为证据；告知用户路径。
```

### Final report

```
## CAG Worktree 结果

任务：<original task>
base 分支：<BASE>
状态：✓ 全部合并 / ⚠ 部分合并 / ✗ 失败

### 子任务
| id | 执行器 | exit | changed | 验证 | 处置 |
|----|--------|------|---------|------|------|
| a  | codex  | 0    | yes     | tests pass | merged |
| b  | agy    | 0    | yes     | build ok   | merged |

### 验证证据（主 Claude 实跑，非 delegate 自述）
- <id a>: <test 命令 + 结果>
- <id b>: <build 命令 + 结果>

### 冲突/拒绝
<如有：哪个分支、原因、是否需人工>

### Artifacts
$HOME/.cache/cag/<repo>/<run>/artifacts/*.md

### 已合并的改动
<git diff --stat 摘要>
```

---

## Boundary recap

| 角色 | 权限 |
|------|------|
| main Claude | 规划 / 拆分 / 建 worktree / review diff / 跑测试 / 合并 / 清理 / 模式选择 |
| codex/agy-delegate (Claude 子 agent) | Read,Grep,Glob,Bash；无 Agent/Edit/Write；只通过 `cag-exec` 在 `$WORKTREE` 内启动 provider 并解析结构化输出，绝不合并、绝不判定完成 |
| codex / agy (provider) | 在 worktree 或工作树内自主改文件（**有沙箱约束**：codex `-s workspace-write`、agy `--sandbox`，可写根锁定工作区），改动被提交到分支等待主 Claude 审查 |
| cag-exec (script) | 咽喉点：worktree 校验（≠主仓库根）+ env strip + provider exec（沙箱 flag：codex `-s workspace-write -C`、agy `--add-dir --sandbox`）+ 越狱哨兵（前后快照对比，provider 改主仓库 → exit 3）+ git commit + 结构化 JSON 输出 |

---

## Safety invariants

- **执行权在 provider**（codex/agy 真改代码）
- **隔离在 worktree + cag-exec 多层防御**：路径校验（≠主仓库根）+ provider 沙箱（codex `-s workspace-write`、agy `--add-dir`/`--sandbox`）+ 越狱哨兵（前后快照对比抓 provider 逃出 worktree 改主仓库 → exit 3）；base 分支只在主 worktree checkout，delegate 切不过去 → 越权 merge 爆炸半径天然受限
- **判定权独占主 Claude**：永远看真实 diff + 真跑测试，绝不信 delegate 自述
