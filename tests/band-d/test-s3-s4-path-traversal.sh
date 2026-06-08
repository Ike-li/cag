#!/usr/bin/env bash
# test-s3-s4-path-traversal.sh: Band D S3-S4 - Path traversal attack tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D S3-S4: 路径遍历攻击测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test S3: Path traversal attack
echo "## S3: 路径遍历攻击（相对路径 + 绝对路径）"
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

echo "➤ Before: 主仓库文件列表"
ls "$TEST_REPO" | grep -v "^\.worktrees$" | sed 's/^/  /'
echo

echo "➤ 执行: mock provider path-traversal 攻击"
cd "$WT"
set +e
RESULT=$(echo "test path traversal" | "$CAG_EXEC" mock "$WT" path-traversal 2>&1)
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

echo "➤ After: ESCAPED_TRAVERSAL.txt 应被清理"
if [[ -f "$TEST_REPO/ESCAPED_TRAVERSAL.txt" ]]; then
  echo "  ✗ 文件仍存在"
  cat "$TEST_REPO/ESCAPED_TRAVERSAL.txt" | sed 's/^/    /'
else
  echo "  ✓ 文件已清理"
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

# Test S4: Home directory escape attack
echo "## S4: $HOME 目录逃逸攻击"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test2"
git worktree add -q "$WT" -b test2 HEAD

echo "✓ 准备：创建测试仓库"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

echo "➤ Before: 检查 ~/cag-test-escape.txt"
if [[ -f ~/cag-test-escape.txt ]]; then
  echo "  ⚠️ 文件已存在，先删除"
  rm -f ~/cag-test-escape.txt
fi
echo "  (不存在)"
echo

echo "➤ 执行: mock provider home-escape 攻击"
cd "$WT"
set +e
RESULT=$(echo "test home escape" | "$CAG_EXEC" mock "$WT" home-escape 2>&1)
EXIT_CODE=$?
set -e
echo "  Exit code: $EXIT_CODE"

# Home escape might NOT trigger sentinel (file is outside git repo)
if [[ $EXIT_CODE -eq 3 ]]; then
  echo "  ⚠️ 哨兵触发 (exit 3) - 意外，$HOME 不在 git 管理"
elif [[ $EXIT_CODE -eq 0 ]]; then
  echo "  ⚠️ 执行成功 (exit 0) - 哨兵未检测到 $HOME 写入"
fi
echo

echo "➤ After: 检查 ~/cag-test-escape.txt"
if [[ -f ~/cag-test-escape.txt ]]; then
  echo "  ⚠️ 文件存在（攻击成功，但不在 git 管理范围）"
  echo "  内容: $(cat ~/cag-test-escape.txt)"
  rm -f ~/cag-test-escape.txt
  echo "  ✓ 已手动清理"
else
  echo "  ✓ 文件不存在（写入失败或被清理）"
fi
echo

echo "➤ 验证: 主仓库 porcelain 状态"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净（预期，$HOME 不在仓库内）"
else
  echo "  ✗ 工作树有改动:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

echo "➤ 结论: S4 Home 逃逸"
echo "  - $HOME 不在 git 管理范围，哨兵无法检测"
echo "  - 这是哨兵的已知限制（只保护 git 仓库）"
echo "  - 缓解措施: agy --sandbox 限制文件系统访问"
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ S3-S4 路径遍历攻击测试完成"
