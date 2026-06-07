# CAG (Claude Autonomous codex/agy orchestrator)

## 定位

Claude Code 编排工具：主 Claude 派发任务给 codex/agy 执行，验证改动，决定是否合并。

## 拓扑

```
~/.claude/skills/cag/             → /Users/raylee/code/cag/skills/cag/        (软链接)
~/.claude/agents/
  ├─ codex-delegate.md            → /Users/raylee/code/cag/agents/codex-delegate.md
  └─ agy-delegate.md              → /Users/raylee/code/cag/agents/agy-delegate.md
~/.local/bin/cag-exec             → /Users/raylee/code/cag/bin/cag-exec
```

## 使用方式

```bash
/cag <task>                       # 自动选模式
/cag codex <task>                 # 强制用 codex（逻辑/重构/测试）
/cag agy <task>                   # 强制用 agy（文档/大上下文）
```

## 工作模式

1. **Direct mode** — 单任务直接改工作树，Claude 审查 diff + 跑测试
2. **Worktree mode** — 多任务并行，每个在独立 worktree 隔离执行

## 核心设计

- **cag-exec** — 咽喉脚本：worktree 校验 + env strip + provider 执行 + git commit + JSON 输出
- **delegates** — 薄执行层：调 cag-exec → 解析 JSON → 返回证据
- **安全约束** — worktree 路径校验（拒绝主仓库根）+ 危险 flag 写死 + 环境变量清理

## 已知限制

- agy 需要 Google 账号认证（OAuth）
- codex 可直接使用（已验证）
- worktree mode 基础设施已验证，完整编排流程待实战测试

## 源码位置

`/Users/raylee/code/cag/` — 独立 git 仓库（通过软链接部署到 ~/.claude/）

## 参考

详细架构和取舍记录见 `README.md`
