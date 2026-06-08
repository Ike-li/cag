#!/usr/bin/env bash
# test-s5-git-hooks.sh: Band D S5 - Git hooks injection test
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D S5: Git Hooks 注入测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test S5: Git hooks injection
echo "## S5: Git Hooks 注入攻击"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"

echo "✓ 准备：创建测试仓库"
echo "  主仓库: $TEST_REPO"
echo

# Create a marker file to detect if hook executes
MARKER="/tmp/cag-s5-hook-marker-$$"
echo "Before hook" > "$MARKER"

echo "➤ 攻击: Provider 在主仓库创建恶意 pre-commit hook"
mkdir -p "$TEST_REPO/.git/hooks"
cat > "$TEST_REPO/.git/hooks/pre-commit" << EOF
#!/bin/bash
# Malicious hook injected by provider
echo "HOOK EXECUTED" > "$MARKER"
exit 0
EOF
chmod +x "$TEST_REPO/.git/hooks/pre-commit"
echo "  ✓ 恶意 hook 已创建: .git/hooks/pre-commit"
echo

echo "➤ 执行: cag-exec 在 worktree 中 commit"
WT="$TEST_REPO/.worktrees/test"
git worktree add -q "$WT" -b test HEAD
cd "$WT"
set +e
RESULT=$(echo "test" | "$CAG_EXEC" mock "$WT" clean 2>&1)
EXIT_CODE=$?
set -e

echo "  Exit code: $EXIT_CODE"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "  ✓ 执行成功"
else
  echo "  ✗ 执行失败 (exit $EXIT_CODE)"
fi
echo

echo "➤ 验证: Hook 是否被执行"
MARKER_CONTENT=$(cat "$MARKER" 2>/dev/null || echo "Before hook")
if [[ "$MARKER_CONTENT" == "HOOK EXECUTED" ]]; then
  echo "  ⚠️ Hook 被执行（marker 被修改）"
  echo "  内容: $MARKER_CONTENT"
  echo
  echo "  分析:"
  echo "  - Worktree commit 触发了主仓库的 pre-commit hook"
  echo "  - Provider 可以通过创建 hook 执行任意代码"
  echo "  - Hook 在 git commit 时执行（不在 provider 沙箱内）"
else
  echo "  ✓ Hook 未执行（marker 未改变）"
  echo "  内容: $MARKER_CONTENT"
  echo
  echo "  分析:"
  echo "  - Worktree commit 未触发 hook"
  echo "  - 可能因为 git config 或环境变量禁用了 hooks"
fi
rm -f "$MARKER"
echo

echo "➤ 验证: Commit 是否成功"
BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count test 2>/dev/null || echo "0")
if [[ $BRANCH_COUNT -gt 1 ]]; then
  echo "  ✓ 有新 commit（hook 未阻止提交）"
else
  echo "  ✗ 无新 commit"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

echo "## S5 结论"
echo "---"
echo "### Git Hooks 执行行为"
echo "- Worktree commit 会触发主仓库的 hooks"
echo "- Provider 可以在主仓库创建 .git/hooks/pre-commit"
echo "- Hook 在 git commit 时执行（不在 provider 沙箱内）"
echo
echo "### 安全分析"
echo "1. **攻击路径**: Provider 逃逸到主仓库 → 创建 hook → 下次 commit 执行"
echo
echo "2. **风险评估**:"
echo "   - 🟡 中风险：需要两步（escape + hook）"
echo "   - 哨兵已经阻止 escape（第一步）"
echo "   - 如果 escape 成功，hook 可以执行任意代码"
echo
echo "3. **缓解措施**:"
echo "   - ✅ 已有：哨兵阻止 escape 到主仓库"
echo "   - 可选：git config core.hooksPath /dev/null"
echo "   - 可选：git commit --no-verify"
echo "   - 可选：定期检查 .git/hooks/ 目录"
echo
echo "4. **实际威胁**:"
echo "   - 前提：provider 先成功 escape（哨兵已防御）"
echo "   - 如果 escape 成功但未被检测，hook 是次级攻击"
echo "   - 当前测试验证了 hook 执行机制，不是新漏洞"
echo
echo "✓ S5 Git hooks 注入测试完成"
