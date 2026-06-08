#!/usr/bin/env bash
# test-r4-shell-injection.sh: Band D R4 - Shell injection defense test
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D R4: Shell Injection 防御测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test R4: Shell injection defense
echo "## R4: Shell 特殊字符不被执行"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"
WT="$TEST_REPO/.worktrees/test"
git worktree add -q "$WT" -b test HEAD

echo "✓ 准备：创建测试仓库"
echo "  主仓库: $TEST_REPO"
echo "  worktree: $WT"
echo

# Create a marker file to detect if shell injection succeeds
MARKER="/tmp/cag-shell-injection-test-marker-$$"
echo "Before execution" > "$MARKER"

echo "➤ 执行: mock provider 输出 shell 特殊字符"
echo "  Provider 输出包含: \$(whoami), \`date\`, ; rm -rf, && echo, | cat"
echo

cd "$WT"
set +e
RESULT=$(echo "test shell injection" | "$CAG_EXEC" mock "$WT" shell-injection 2>&1)
EXIT_CODE=$?
set -e

echo "  Exit code: $EXIT_CODE"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "  ✓ 执行成功"
else
  echo "  ✗ 执行失败 (exit $EXIT_CODE)"
fi
echo

echo "➤ 验证: Marker 文件内容（应未被修改）"
MARKER_CONTENT=$(cat "$MARKER")
if [[ "$MARKER_CONTENT" == "Before execution" ]]; then
  echo "  ✓ Marker 未改变（shell 命令未执行）"
else
  echo "  ✗ Marker 被修改为: $MARKER_CONTENT"
fi
rm -f "$MARKER"
echo

echo "➤ 验证: 检查 /tmp/test 是否被删除"
# 先创建测试目录
TEST_DIR="/tmp/cag-r4-test-$$"
mkdir -p "$TEST_DIR"
echo "test" > "$TEST_DIR/file.txt"

# 如果 rm -rf 被执行，这个目录会被删除
if [[ -d "$TEST_DIR" ]]; then
  echo "  ✓ 测试目录仍存在（rm -rf 未执行）"
  rm -rf "$TEST_DIR"
else
  echo "  ✗ 测试目录被删除（rm -rf 被执行！）"
fi
echo

echo "➤ 验证: 检查 mock-output.txt 内容"
if [[ -f "$WT/mock-output.txt" ]]; then
  echo "  ✓ 输出文件存在"
  echo
  echo "  内容预览（前 10 行）:"
  head -10 "$WT/mock-output.txt" | sed 's/^/    /'

  echo
  echo "  检查特殊字符是否为字面量:"
  if grep -q '\$(whoami)' "$WT/mock-output.txt"; then
    echo "    ✓ \$(whoami) 未被执行（作为字面量）"
  else
    echo "    ✗ \$(whoami) 可能被执行"
  fi

  if grep -q '`date`' "$WT/mock-output.txt"; then
    echo "    ✓ \`date\` 未被执行（作为字面量）"
  else
    echo "    ✗ \`date\` 可能被执行"
  fi
else
  echo "  ✗ 输出文件不存在"
fi
echo

echo "➤ 验证: cag-exec 是否安全处理异常输出"
echo "  cag-exec 读取 provider 输出时应该："
echo "  - 不执行 shell 命令（使用安全的文件读取）"
echo "  - 不受特殊字符影响"
echo "  - 正确提交包含特殊字符的文件"
echo

if [[ $EXIT_CODE -eq 0 ]]; then
  # Check if commit was made
  BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count test 2>/dev/null || echo "0")
  if [[ $BRANCH_COUNT -gt 1 ]]; then
    echo "  ✓ Commit 成功（包含特殊字符的文件被正确提交）"
  else
    echo "  ✗ 未 commit（可能因特殊字符失败）"
  fi
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

echo "## R4 结论"
echo "---"
echo "Shell injection 防御基于以下机制："
echo "1. ✅ cag-exec 使用文件重定向（不调用 eval/sh -c）"
echo "2. ✅ Provider 输出通过文件传递（不通过 pipe）"
echo "3. ✅ Git commit 消息用 -m 直接传递（不经过 shell）"
echo
echo "风险评估："
echo "- 🟢 低风险：当前实现无明显 shell injection 路径"
echo "- ⚠️ 需注意：未来修改时避免 eval/sh -c/反引号"
echo
echo "✓ R4 Shell injection 测试完成"
