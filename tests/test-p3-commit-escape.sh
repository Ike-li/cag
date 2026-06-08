#!/usr/bin/env bash
# test-p3-commit-escape.sh: End-to-end test for P3 commit escape detection
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  P3 端到端测试：Commit Escape 检测"
echo "════════════════════════════════════════════════════════════════"
echo

# Test 1: Commit escape detection
echo "## Test 1: Commit Escape 检测"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test1"
git worktree add -q "$WT" -b test1 HEAD

echo "✓ 准备：创建测试仓库"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

echo "➤ Before: HEAD hash"
BEFORE_HASH=$(git -C "$TEST_REPO" rev-parse HEAD)
echo "  $BEFORE_HASH"
echo

echo "➤ Before: git log"
git -C "$TEST_REPO" log --oneline | head -3 | sed 's/^/  /'
echo

echo "➤ 执行: mock provider (commit 逃逸)"
cd "$WT"
set +e
RESULT=$(echo "test commit escape" | "$CAG_EXEC" mock "$WT" commit 2>&1)
EXIT_CODE=$?
set -e
echo "  Exit code: $EXIT_CODE"
if [[ $EXIT_CODE -eq 3 ]]; then
  echo "  ✓ 哨兵触发 (exit 3)"
else
  echo "  ✗ 预期 exit 3，实际 $EXIT_CODE"
fi
echo

echo "➤ 错误信息:"
echo "$RESULT" | jq -r '.error' 2>/dev/null | sed 's/^/  /' || echo "$RESULT" | grep -o "SANDBOX ESCAPE" | sed 's/^/  /' || echo "  (无)"
echo

echo "➤ After: HEAD hash（应被恢复）"
AFTER_HASH=$(git -C "$TEST_REPO" rev-parse HEAD)
echo "  $AFTER_HASH"
if [[ "$AFTER_HASH" == "$BEFORE_HASH" ]]; then
  echo "  ✓ HEAD 已恢复（P3 检测 + P2 清理成功）"
else
  echo "  ✗ HEAD 未恢复，commit 仍存在"
fi
echo

echo "➤ After: git log"
git -C "$TEST_REPO" log --oneline | head -3 | sed 's/^/  /'
echo

echo "➤ 验证: ESCAPED_COMMITTED.txt 应不存在"
if [[ -f "$TEST_REPO/ESCAPED_COMMITTED.txt" ]]; then
  echo "  ✗ 文件仍存在（清理失败）"
  cat "$TEST_REPO/ESCAPED_COMMITTED.txt" | sed 's/^/    /'
else
  echo "  ✓ 文件已清理"
fi
echo

echo "➤ 验证: porcelain 状态（应干净）"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净（P2 清理成功）"
else
  echo "  ✗ 工作树有残留:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test 2: Commit + clean worktree escape (狡猾场景)
echo "## Test 2: Commit + 清理工作树（绕过 porcelain 的狡猾逃逸）"
echo "---"
echo "说明: 这种场景下，provider 先 commit，再清理工作树，"
echo "      使得 porcelain 前后一致，只有 HEAD hash 能检测到。"
echo

TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test2"
git worktree add -q "$WT" -b test2 HEAD

echo "✓ 准备：创建测试仓库"
echo

echo "➤ Before: HEAD + porcelain"
BEFORE_HASH=$(git -C "$TEST_REPO" rev-parse HEAD)
BEFORE_PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
echo "  HEAD: ${BEFORE_HASH:0:8}"
echo "  porcelain: ${BEFORE_PORCELAIN:-(空)}"
echo

echo "➤ 执行: 狡猾逃逸模拟"
echo "  (手动模拟：commit 后清理工作树)"
cd "$TEST_REPO"
echo "escaped" > SNEAKY.txt
git add SNEAKY.txt && git commit -qm "sneaky escape"
# 现在清理工作树（让 porcelain 看起来干净）
git rm -q SNEAKY.txt && git commit -qm "cover tracks"

AFTER_HASH=$(git -C "$TEST_REPO" rev-parse HEAD)
AFTER_PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
echo "  HEAD: ${AFTER_HASH:0:8} (changed)"
echo "  porcelain: ${AFTER_PORCELAIN:-(空)} (看起来干净)"
echo

echo "➤ 验证: P3 能检测到吗？"
if [[ "$AFTER_HASH" != "$BEFORE_HASH" ]]; then
  echo "  ✓ HEAD hash 不同（P3 能检测到这种逃逸）"
else
  echo "  ✗ HEAD hash 相同（P3 检测失败）"
fi
echo

if [[ -z "$AFTER_PORCELAIN" ]]; then
  echo "  ⚠️ porcelain 干净（只检查 porcelain 会漏报）"
else
  echo "  porcelain 有变化"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ P3 端到端测试完成"
