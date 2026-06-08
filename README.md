# CAG — Claude Code 编排 codex/agy 执行、Claude 验证
<!-- CAG v2.1 - 智能模型选择 -->

独立的 CAG 项目仓库。通过软链接部署到 `~/.claude/`（agents + skills）和 `~/.local/bin/`（cag-exec）。

```bash
# 部署软链接（首次安装或迁移后）
ln -sfn /Users/raylee/code/cag/skills/cag ~/.claude/skills/cag
ln -sfn /Users/raylee/code/cag/agents/codex-delegate.md ~/.claude/agents/codex-delegate.md
ln -sfn /Users/raylee/code/cag/agents/agy-delegate.md ~/.claude/agents/agy-delegate.md
ln -sfn /Users/raylee/code/cag/bin/cag-exec ~/.local/bin/cag-exec
```

直接编辑本仓库文件即可生效，无需复制。

## 现状 — v2 最优方案（已落地）

### 核心架构
- **`bin/cag-exec`** — 咽喉脚本（zsh）：worktree 校验（≠主仓库根）+ env strip + 跑 provider（支持可选 model/reasoning 参数）+ **越狱哨兵**（provider 跑完后对比主仓库工作树前后快照，发现 provider 改了 worktree 以外的主仓库 → 报 `SANDBOX ESCAPE` + exit 3，拒绝 commit）+ `git add -A && commit` + 结构化 JSON 输出。支持 `--dry-run`（provider 正常运行，跳过 commit，输出 diff）。把散文安全约束变成代码硬约束。provider 沙箱收紧（替代原先的"危险 flag 写死"）：agy 用 `--add-dir $WORKTREE`（锁 workspace）+ `--sandbox`；codex 用 `-s workspace-write -C $WORKTREE`（原生进程内沙箱，拒绝写 worktree 外）。两者均非交互、不卡审批。
- **`agents/codex-delegate.md` / `agy-delegate.md`** — 执行型 subagent（已改薄）：调 `cag-exec` → 解析 JSON → 返回 diff 证据。tools 白名单 Read,Grep,Glob,Bash；无 Agent/Edit/Write；model sonnet。支持 MODEL/REASONING 参数传递。
- **`skills/cag/SKILL.md`** — 统一编排器：自动选 direct mode（单任务直接改工作树）或 worktree mode（多任务并行隔离）。**主 Claude 根据任务难度智能选择 provider、model 和 reasoning effort**。
- **`MODEL_SELECTION.md`** — 智能模型选择指南：决策矩阵、成本优化、示例场景。

### 验证记录
- v1 实测通过：codex/agy 均能自主改文件；worktree 全链路（建→改→提交→review→测试→合并→清理）验证通过；Bash 工具实际跑 zsh（已避开 PIPESTATUS bashism）。
- v2 改进：delegate 从 ~80 行减到 ~60 行（inline bash → cag-exec 调用）；统一 skill 自动选模式；咽喉脚本集中安全策略。
- **v2.1 新增**：智能模型选择 — 主 Claude 根据任务类型（算法/文档/重构）、复杂度自动选择 model（gpt-5.5/o3/gemini-2.0-flash-thinking）和 reasoning effort（low/medium/high/xhigh）。成本优化：简单任务降级到 gpt-4o + low，复杂算法升级到 o3 + xhigh。
- **v2.2 新增**：dry-run 模式 — `cag-exec --dry-run` 让 provider 运行、不提交，只输出 diff；`/cag --dry-run <task>` 透传到 cag-exec。

### 已归档（v1）
- `skills/cag-ultrawork/SKILL.md` — 并行 worktree 编排（已合并到 `/cag` worktree mode）
- `skills/dispatch-cli/SKILL.md` — 单任务直接改工作树（已合并到 `/cag` direct mode）

## 三条不变量
- 执行权在 provider（codex/agy 真改代码）
- 隔离在 worktree + cag-exec 多层防御：路径校验（≠主仓库根）+ agy `--add-dir`/`--sandbox`（约束 provider）+ 越狱哨兵（前后快照对比，抓 provider 逃出 worktree 改主仓库）；base 分支只在主 worktree checkout，delegate 切不过去→越权 merge 爆炸半径天然受限
- 判定权独占主 Claude：永远看真实 diff + 真跑测试，绝不信 delegate 自述

## 取舍记录
- 用手动 git worktree(从 HEAD)，弃 `isolation:worktree` frontmatter（它从默认分支切、丢合并控制权）
- 用并行 fan-out，弃原生 Teams（独立任务不需 worker 互通，过重）
- 最优=1 脚本(cag-exec)；最轻=0 脚本(纯 markdown 散文约束)。本方案选最优。

## 部署状态

CAG v2.1 已部署，软链接指向本仓库，codex/agy provider 均可用。
