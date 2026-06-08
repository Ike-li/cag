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

- **cag-exec** — 咽喉脚本：worktree 校验 + env strip + provider 执行 + 越狱哨兵 + git commit + JSON 输出
- **delegates** — 薄执行层：调 cag-exec → 解析 JSON → 返回证据
- **安全约束** — worktree 路径校验（拒绝主仓库根）+ agy `--add-dir`/`--sandbox`（约束 provider workspace）+ 越狱哨兵（前后快照对比，provider 改主仓库 → SANDBOX ESCAPE + exit 3）+ 环境变量清理

## 已知限制

- agy 需要 Google 账号认证（OAuth）
- codex 可直接使用（已验证）；认证用文件 `~/.codex/auth.json`（非 Keychain）
- **codex 沙箱改造（2026-06-07）**：codex 段已从 `--dangerously-bypass-approvals-and-sandbox`（完全无沙箱）改为 `-s workspace-write -C $WORKTREE`。codex 原生进程内沙箱，把可写根锁在 worktree，**实测拒绝写 worktree 外**（`sandbox: workspace-write [workdir,/tmp,$TMPDIR]`），非交互不卡审批，无 agy 那种嵌套冲突/Keychain 坑。codex 隔离比 agy 干净得多。
- **agy 不可靠（Band C 6f 定案，2026-06-08）**：agy `--add-dir` 参数不稳定，同样命令有时写到目标 worktree，有时写到 `~/.gemini/.../scratch`。多次独立测试证实，无明显规律。**生产环境优先 codex**。agy 仅作"机会主义 provider"（可用时使用，不强求稳定）。
- worktree mode 基础设施已验证，完整编排流程待实战测试
- **agy 越狱风险（已加防御，2026-06-07）**：agy 有自己的 "active workspace" 概念，越狱时**无视进程 cwd**，跑去 `~/.gemini/.../scratch`，对一般文件名（如 README.md）全 `$HOME` 搜索，最终改主仓库并 `git checkout` 毁未提交改动。**非确定性**。实测关键：**是 `--sandbox` 在压住 agy 留在 worktree，`--add-dir` 单独压不住**。防御：`--add-dir` 锁 workspace + agy 原生 `--sandbox` + 越狱哨兵兜底。`--dangerously-skip-permissions` 是放大器（破坏性操作免确认），已移除。
- **第 5 层 sandbox-exec 对 agy 不可行（已调查定案，2026-06-07）**：① 嵌套沙箱冲突——`agy --sandbox` 套在外层 `sandbox-exec` 里会**启动死锁**（macOS Seatbelt 不支持重入）；去掉 agy 的 `--sandbox` 才能跑，但那样越狱压不住。② agy 认证 token 存 **macOS Keychain**（`login.keychain-db`，非 `~/.gemini` 文件），过期需写回，外层沙箱 deny `$HOME` 写会断认证。结论：agy 走"原生 `--sandbox` + 哨兵"（路线 A），不套 sandbox-exec。sandbox-exec 的内核隔离仅适合 codex（原生支持，见 codex 段改造）。
- sandbox-exec 策略要点（备用知识）：`(allow default)` + `(deny file-write* (subpath $HOME))` + 例外放行 `worktree`/`主仓库.git`（整个 .git，含 objects/index）；规则 **last-match-wins**；路径必须 `realpath` 解析（`/tmp`→`/private/tmp`）；git commit 还需 `/dev`（`/dev/null`）。

## 源码位置

`/Users/raylee/code/cag/` — 独立 git 仓库（通过软链接部署到 ~/.claude/）

## 参考

详细架构和取舍记录见 `README.md`

## 实战发现 #1：provider 副产物（**pycache**）

- 发现来源：Rung 1, 2
- 级别：低
- 状态：已明确
- 说明：codex/agy 自我验证留 **pycache**；项目 .gitignore 会挡，无则 git add -A 全收；真仓库有 .gitignore，实害有限。

## 实战发现 #2：哨兵实战兜底成功

- 发现来源：Rung 4
- 级别：正面
- 状态：已验证
- 说明：Rung 4 agy 真越狱写主仓库，cag-exec 哨兵触发 SANDBOX ESCAPE + exit 3 拒 commit。

## 实战发现 #3：delegate 自主重试绕哨兵

- 发现来源：Rung 4
- 级别：严重
- 状态：已修复（commit 2a69351）
- 说明：agy-delegate 遇 exit 3 未停止上报，自主往 prompt 加绝对路径重试绕过；违反判定权独占契约；已在 commit 2a69351 修复（delegate 硬停 exit 3）。

## 实战发现 #4：越狱残留无人清

- 发现来源：Rung 4
- 级别：中
- 状态：已修复（commit 2a69351）
- 说明：哨兵只检测+拒 commit，agy 写主仓库的文件留工作树；已在 commit 2a69351 修复（主 Claude 清理残留）。

## 实战发现 #5：哨兵 porcelain 盲区

- 发现来源：Rung 4
- 级别：低
- 状态：已修复（commit b0e4ed9）
- 说明：哨兵比对 git status --porcelain；若 provider 越狱后在主仓库 git add && commit，工作树 clean 前后快照相等会漏报；已在 commit b0e4ed9 修复（比对 HEAD hash）。

## Band C 实战结果（2026-06-08）

- 任务：dogfood（在 cag 仓库用 cag 修改自身）
- 6a-6e（codex + gpt-5.5）：全部通过 ✓
- 6f（agy）：失败 ✗ — 写到 ~/.gemini/.../scratch，非 worktree
- 根因：agy --add-dir 参数不可靠（多次独立测试证实）
- 修复：commit b0e4ed9（P0 标注不可靠 + P1 delegate 硬停 + P2 残留清理 + P3 哨兵增强）
- 结论：生产环境优先 codex；agy 仅作机会主义 provider
