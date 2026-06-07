# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## 架构概述

CAG 是一个**元工具**——Claude Code 通过它编排其他 AI 编码工具（codex/agy）执行代码改动，主 Claude 负责验证和合并。

### 运行时调用链

```
/cag <task>                          # 用户调用 skill
  └─ skills/cag/SKILL.md             # 编排器：选模式（direct/worktree）、选 provider
       ├─ direct mode: 直接调 codex/agy 在当前工作树改文件
       └─ worktree mode: 派发 delegate subagent
            └─ agents/*-delegate.md  # 薄执行层：调 cag-exec → 解析 JSON → 返回证据
                 └─ bin/cag-exec     # 咽喉脚本：校验 → 执行 → 提交 → JSON 输出
                      └─ codex/agy   # 真正改文件的 AI provider
```

### 部署拓扑（软链接）

```
~/.claude/skills/cag/          → 本仓库 skills/cag/
~/.claude/agents/codex-delegate.md → 本仓库 agents/codex-delegate.md
~/.claude/agents/agy-delegate.md   → 本仓库 agents/agy-delegate.md
~/.local/bin/cag-exec             → 本仓库 bin/cag-exec
```

直接编辑本仓库文件即生效（skill 自动重载，agent 定义需重启 Claude Code）。

## 常用命令

```bash
# 验证 cag-exec 语法和基本行为
bash -n bin/cag-exec
cag-exec 2>&1 | head -1
# 预期：{"error":"usage: cag-exec <codex|agy> ..."}

# 验证软链接完整性
ls -la ~/.claude/skills/cag ~/.claude/agents/codex-delegate.md ~/.claude/agents/agy-delegate.md ~/.local/bin/cag-exec

# 确认 provider 可用
which codex agy
```

## 关键约束

- **codex 仅支持 gpt-5.5**（ChatGPT 账号限制）。传递 gpt-4o/o3 会快速失败（cag-exec 预检查拦截）。建议不传 MODEL 参数。
- **agy 不支持 reasoning effort 参数**，只能通过 model 选择控制质量。
- **cag-exec 拒绝在主仓库根执行**（`.git` 是目录而非文件 → 拒绝），确保改动只在 worktree 内发生。
- **delegate 无 Agent/Edit/Write 工具**，只能通过 cag-exec 调用 provider 改文件。

## 验证流程（主 Claude 的核心职责）

无论 direct 还是 worktree 模式，主 Claude 必须：

1. **审查真实 diff**：`git diff` 或 `git show`，绝不信 delegate 自述
2. **真跑测试/构建**：在 worktree 或工作树内实际执行验证命令
3. **决策**：pass（合并/提交）/ fix（重跑最多 2-3 轮）/ reject（回滚）

详见 `skills/cag/SKILL.md` 中的 Step 2 (direct) 和 Step 4 (worktree)。
