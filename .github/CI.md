# CI/CD 配置说明

本文档描述 CAG 项目的持续集成（CI）和本地开发工具配置。

---

## Pre-commit Hooks

### 安装

项目使用 [pre-commit](https://pre-commit.com) 管理 Git hooks。

**首次设置**:
```bash
# 安装 pre-commit（如果未安装）
pip install pre-commit
# 或
brew install pre-commit

# 安装 hooks 到 .git/hooks/
pre-commit install
```

### 配置的 Hooks

**.pre-commit-config.yaml**:

1. **trailing-whitespace**: 清理行尾空格
2. **end-of-file-fixer**: 确保文件以换行符结尾
3. **check-yaml**: YAML 语法检查
4. **check-added-large-files**: 防止提交大文件（>1MB）
5. **check-merge-conflict**: 检测 merge conflict markers
6. **check-executables-have-shebangs**: 确保脚本有 shebang
7. **shellcheck**: Shell 脚本静态分析（仅 error 级别）
8. **markdownlint**: Markdown 格式检查（手动模式）

### 使用

**自动运行**（每次 `git commit` 时）:
```bash
git commit -m "your message"
# pre-commit 自动运行，修复简单问题
```

**手动运行**（检查所有文件）:
```bash
pre-commit run --all-files
```

**跳过 hooks**（紧急情况）:
```bash
git commit --no-verify -m "emergency fix"
```

### 自定义配置

**.markdownlint.yaml**: Markdown 规则配置
- 行长度限制：120 字符
- 允许 inline HTML
- 允许重复标题
- 禁用中文锚点检查

---

## GitHub Actions

### Workflow: Band D Tests

**文件**: `.github/workflows/band-d-tests.yml`

**触发条件**:

- Push 到 `main` 或 `develop` 分支
- Pull Request 到 `main` 分支
- 修改 `bin/`、`tests/` 或 workflow 文件时
- 手动触发（workflow_dispatch）

**运行环境**:

- OS: Ubuntu Latest
- 超时: 15 分钟

---

## 测试阶段

### P0: Core Defense（必须通过）

- S1-S2: 符号链接攻击
- C1-C3: 并发压力（串行/低/中）
- A1: 对抗基线

**失败策略**: P0 失败 → CI 失败

---

### P1: High-Value Scenarios（允许部分失败）

- S3-S4: 路径遍历
- C5: 混合并发
- R4: Shell injection

**失败策略**: P1 失败 → CI 继续（已知限制：S4, C5）

---

### P2: Edge Cases（必须通过）

- R1-R3: Provider 错误处理
- C4: 高并发（10 worktree）
- S5: Git hooks 注入

**失败策略**: P2 失败 → CI 失败

---

## CI 报告

每次运行生成测试摘要（GitHub Actions Summary）：

```
# Band D Test Results

| Phase | Status |
|-------|--------|
| P0 Core Defense | ✅ Pass |
| P1 High-Value | ⚠️ Known Issues |
| P2 Edge Cases | ✅ Pass |

See TESTING.md for detailed test documentation.
```

---

## 本地运行

在提交前本地运行所有测试：

```bash
# 运行所有 Band D 测试
for test in tests/band-d/test-*.sh; do
  echo "=== Running $(basename $test) ==="
  "$test" || echo "FAILED: $test"
  echo
done
```

或单独运行某个阶段：

```bash
# P0
tests/band-d/test-s1-s2-symlink-attacks.sh
tests/band-d/test-c1-c3-concurrency.sh
tests/band-d/test-a1-adversarial-baseline.sh

# P1
tests/band-d/test-s3-s4-path-traversal.sh
tests/band-d/test-c5-mixed-concurrency.sh
tests/band-d/test-r4-shell-injection.sh

# P2
tests/band-d/test-r1-r3-provider-errors.sh
tests/band-d/test-c4-high-concurrency.sh
tests/band-d/test-s5-git-hooks.sh
```

---

## 环境要求

CI 需要以下环境：

- ✅ Git（测试创建临时仓库）
- ✅ Bash/Zsh（测试脚本）
- ✅ `bin/mock-provider`（模拟 provider）
- ✅ `bin/cag-exec`（被测对象）

**不需要**:

- ❌ 真实 codex/agy（使用 mock-provider）
- ❌ Claude Code（测试是独立的）
- ❌ 外部依赖（所有测试使用临时目录）

---

## 调试失败的 CI

### 1. 查看 GitHub Actions 日志

在 GitHub 仓库的 "Actions" 标签页查看：

- 每个测试步骤的详细输出
- 失败的具体错误信息
- 测试摘要

### 2. 本地复现

```bash
# 设置相同的环境
git config --global user.name "CI Bot"
git config --global user.email "ci@example.com"

# 运行失败的测试
tests/band-d/test-xxx.sh
```

### 3. 常见问题

**问题**: 测试超时

- **原因**: 并发测试卡住
- **解决**: 检查 `git worktree` 是否正常工作

**问题**: Git 权限错误

- **原因**: CI 环境 git config 未设置
- **解决**: Workflow 已自动配置 user.name 和 user.email

**问题**: 文件权限错误

- **原因**: 测试脚本不可执行
- **解决**: Workflow 已自动 `chmod +x`

---

## 修改 CI 配置

### 添加新测试

1. 在 `tests/band-d/` 添加新测试脚本
2. 在 workflow 中添加步骤：

   ```yaml
   - name: Run New Test
     run: |
       echo "::group::New Test Name"
       tests/band-d/test-new.sh
       echo "::endgroup::"
   ```

### 修改失败策略

编辑 `.github/workflows/band-d-tests.yml`：

- `continue-on-error: true` → 失败后继续
- `continue-on-error: false` → 失败后停止

### 修改触发条件

编辑 workflow 的 `on` 部分：

```yaml
on:
  push:
    branches: [ main, develop, feature/* ]  # 添加分支
  schedule:
    - cron: '0 0 * * *'  # 每天运行
```

---

## Badge 状态徽章

在 README.md 中添加 CI 状态徽章：

```markdown
[![Band D Tests](https://github.com/USERNAME/cag/workflows/Band%20D%20Tests/badge.svg)](https://github.com/USERNAME/cag/actions)
```

将 `USERNAME` 替换为实际的 GitHub 用户名。

---

## 未来改进

### 可选增强

1. **测试覆盖率报告**
   - 添加覆盖率工具
   - 上传到 Codecov

2. **性能监控**
   - 记录每个测试的执行时间
   - 检测性能回归

3. **并行执行**
   - 将 P0/P1/P2 并行运行
   - 减少 CI 时间

4. **测试矩阵**
   - 在多个 OS 上运行（macOS, Ubuntu）
   - 测试不同 shell（bash, zsh）

---

**最后更新**: 2026-06-08  
**维护者**: Claude Code (Opus 4.8)
