#!/usr/bin/env bash
# test-p2-cleanup.sh: End-to-end test for P2 sentinel cleanup logic
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  P2 端到端测试：哨兵清理越狱残留"
echo "════════════════════════════════════════════════════════════════"
echo

# Test 1: Untracked file escape
echo "## Test 1: Untracked 文件逃逸"
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

echo "➤ Before: 主仓库状态"
git -C "$TEST_REPO" status --porcelain
echo "  (空 = 干净)"
echo

echo "➤ 执行: mock provider (untracked 逃逸)"
set +e
RESULT=$(echo "test untracked escape" | "$CAG_EXEC" mock "$WT" untracked 2>&1)
EXIT_CODE=$?
set -e
echo "  Exit code: $EXIT_CODE"
if [[ $EXIT_CODE -eq 3 ]]; then
  echo "  ✓ 哨兵触发 (exit 3)"
else
  echo "  ✗ 预期 exit 3，实际 $EXIT_CODE"
fi
echo

echo "➤ After: 主仓库状态（应被清理）"
AFTER=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$AFTER" ]]; then
  echo "  ✓ 工作树干净（P2 清理成功）"
else
  echo "  ✗ 工作树仍有残留:"
  echo "$AFTER" | sed 's/^/    /'
fi
echo

echo "➤ 验证: ESCAPED_UNTRACKED.txt 应不存在"
if [[ -f "$TEST_REPO/ESCAPED_UNTRACKED.txt" ]]; then
  echo "  ✗ 文件仍存在（清理失败）"
  cat "$TEST_REPO/ESCAPED_UNTRACKED.txt" | sed 's/^/    /'
else
  echo "  ✓ 文件已清理"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test 2: Modified file escape
echo "## Test 2: Modified 文件逃逸"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "original content" > target.txt
git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test2"
git worktree add -q "$WT" -b test2 HEAD

echo "✓ 准备：创建测试仓库（含 target.txt）"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

echo "➤ Before: target.txt 内容"
cat "$TEST_REPO/target.txt" | sed 's/^/  /'
echo

echo "➤ 执行: mock provider (modified 逃逸)"
set +e
RESULT=$(echo "test modified escape" | "$CAG_EXEC" mock "$WT" modified 2>&1)
EXIT_CODE=$?
set -e
echo "  Exit code: $EXIT_CODE"
if [[ $EXIT_CODE -eq 3 ]]; then
  echo "  ✓ 哨兵触发 (exit 3)"
else
  echo "  ✗ 预期 exit 3，实际 $EXIT_CODE"
fi
echo

echo "➤ After: target.txt 内容（应被恢复）"
cat "$TEST_REPO/target.txt" | sed 's/^/  /'
CONTENT=$(cat "$TEST_REPO/target.txt")
if [[ "$CONTENT" == "original content" ]]; then
  echo "  ✓ 内容已恢复（P2 清理成功）"
else
  echo "  ✗ 内容未恢复，仍包含逃逸痕迹"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test 3: Clean behavior (control)
echo "## Test 3: Clean 行为（控制组）"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test3"
git worktree add -q "$WT" -b test3 HEAD

echo "✓ 准备：创建测试仓库"
echo

echo "➤ 执行: mock provider (clean 行为)"
RESULT=$(echo "test clean behavior" | "$CAG_EXEC" mock "$WT" clean 2>&1)
EXIT_CODE=$?
echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
echo

if [[ $EXIT_CODE -eq 0 ]]; then
  echo "  ✓ 正常完成 (exit 0)"
  CHANGED=$(echo "$RESULT" | jq -r '.changed' 2>/dev/null || echo "unknown")
  echo "  changed: $CHANGED"
  if [[ "$CHANGED" == "true" ]]; then
    echo "  ✓ worktree 有改动（正常）"
  fi
else
  echo "  ✗ 预期 exit 0，实际 $EXIT_CODE"
fi
echo

echo "➤ 验证: 主仓库应无改动"
MAIN_STATUS=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$MAIN_STATUS" ]]; then
  echo "  ✓ 主仓库干净（未逃逸）"
else
  echo "  ✗ 主仓库有改动:"
  echo "$MAIN_STATUS" | sed 's/^/    /'
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ P2 端到端测试完成"
