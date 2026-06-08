#!/usr/bin/env bash
# test-s1-s2-symlink-attacks.sh: Band D S1-S2 - Symlink attack tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D S1-S2: 符号链接攻击测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test S1: Symlink file attack
echo "## S1: 符号链接文件攻击"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
echo "original content" > target.txt && git add -A && git commit -qm "add target"
WT="$TEST_REPO/.worktrees/test1"
git worktree add -q "$WT" -b test1 HEAD

echo "✓ 准备：创建测试仓库（含 target.txt）"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

echo "➤ Before: target.txt 内容"
cat "$TEST_REPO/target.txt" | sed 's/^/  /'
echo

echo "➤ 执行: mock provider symlink-file 攻击"
cd "$WT"
set +e
RESULT=$(echo "test symlink file attack" | "$CAG_EXEC" mock "$WT" symlink-file 2>&1)
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
echo "$RESULT" | jq -r '.error' 2>/dev/null | sed 's/^/  /' || echo "  (无 JSON 输出)"
echo

echo "➤ After: target.txt 内容（应被恢复）"
TARGET_CONTENT=$(cat "$TEST_REPO/target.txt")
echo "$TARGET_CONTENT" | sed 's/^/  /'
if [[ "$TARGET_CONTENT" == "original content" ]]; then
  echo "  ✓ 内容已恢复（P2 清理成功）"
else
  echo "  ✗ 内容包含攻击痕迹（清理失败）"
fi
echo

echo "➤ 验证: fake.txt 符号链接应被清理"
if [[ -e "$WT/fake.txt" ]]; then
  echo "  ✗ 符号链接仍存在"
  ls -la "$WT/fake.txt" | sed 's/^/    /'
else
  echo "  ✓ 符号链接已清理"
fi
echo

echo "➤ 验证: 主仓库 porcelain 状态（应干净）"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净"
else
  echo "  ✗ 工作树有残留:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test S2: Symlink directory attack
echo "## S2: 符号链接目录攻击"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
mkdir -p targetdir && echo "original" > targetdir/file.txt
git add -A && git commit -qm "add targetdir"
WT="$TEST_REPO/.worktrees/test2"
git worktree add -q "$WT" -b test2 HEAD

echo "✓ 准备：创建测试仓库（含 targetdir/file.txt）"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

echo "➤ Before: targetdir/file.txt 内容"
cat "$TEST_REPO/targetdir/file.txt" | sed 's/^/  /'
echo

echo "➤ 执行: mock provider symlink-dir 攻击"
cd "$WT"
set +e
RESULT=$(echo "test symlink dir attack" | "$CAG_EXEC" mock "$WT" symlink-dir 2>&1)
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
echo "$RESULT" | jq -r '.error' 2>/dev/null | sed 's/^/  /' || echo "  (无 JSON 输出)"
echo

echo "➤ After: targetdir/file.txt 内容（应被恢复）"
DIR_CONTENT=$(cat "$TEST_REPO/targetdir/file.txt")
echo "$DIR_CONTENT" | sed 's/^/  /'
if [[ "$DIR_CONTENT" == "original" ]]; then
  echo "  ✓ 内容已恢复（P2 清理成功）"
else
  echo "  ✗ 内容包含攻击痕迹（清理失败）"
fi
echo

echo "➤ 验证: fakedir 符号链接应被清理"
if [[ -e "$WT/fakedir" ]]; then
  echo "  ✗ 符号链接仍存在"
  ls -la "$WT/fakedir" | sed 's/^/    /'
else
  echo "  ✓ 符号链接已清理"
fi
echo

echo "➤ 验证: 主仓库 porcelain 状态（应干净）"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净"
else
  echo "  ✗ 工作树有残留:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ S1-S2 符号链接攻击测试完成"
