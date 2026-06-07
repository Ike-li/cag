# AGENTS.md

This file provides guidance to Codex/agents when working in this repository.

## Purpose

CAG（Claude Autonomous codex/agy orchestrator）— Claude Code 编排 codex/agy 执行代码改动，主 Claude 验证并合并。

## Preferences

- 语言：中文交流。
- 和软件相关的修改遵循 TDD；先明确验证方式，再改动，再运行验证。
- 不把 token、API key、私钥、代理节点信息写进仓库。

## Project Rules

- 先读 `README.md` 和 `memory.md` 了解架构。
- 修改 agent 定义（`agents/*.md`）后需重启 Claude Code 才能生效。
- 修改 `skills/cag/SKILL.md` 后 `/cag` skill 会自动重新加载。
- 修改 `bin/cag-exec` 是咽喉脚本，需谨慎：它集中了 worktree 校验、env strip、provider 执行和 git commit。
- 软链接是部署方式：`~/.claude/skills/cag`、`~/.claude/agents/*.md`、`~/.local/bin/cag-exec` 指向本仓库。

## Three Invariants

- **执行权在 provider**（codex/agy 真改代码）
- **隔离在 worktree + cag-exec 路径校验**（双保险）
- **判定权独占主 Claude**：永远看真实 diff + 真跑测试，绝不信 delegate 自述

## Layout

```text
.
├── README.md              # 架构文档
├── MODEL_SELECTION.md      # 智能模型选择指南
├── memory.md               # 事实记忆
├── AGENTS.md               # Agent 工作指引
├── CLAUDE.md               # Claude Code 入口
├── agents/
│   ├── codex-delegate.md   # Codex 执行型 subagent
│   └── agy-delegate.md     # Agy 执行型 subagent
├── bin/
│   └── cag-exec            # 咽喉脚本
└── skills/
    └── cag/
        └── SKILL.md        # 统一编排 skill
```

## Verification

修改 `bin/cag-exec` 后：

```bash
bash -n bin/cag-exec
cag-exec 2>&1 | head -1
# 预期：{"error":"usage: cag-exec <codex|agy> ..."}
```
