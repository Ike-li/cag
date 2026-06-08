#!/usr/bin/env bash
# test-c4-high-concurrency.sh: Band D C4 - High concurrency test (10 worktrees)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D C4: 高并发测试（10 worktree）"
echo "════════════════════════════════════════════════════════════════"
echo

# Test C4: High concurrency (10 parallel worktrees)
echo "## C4: 高并发（10 clean 任务并行）"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"

echo "✓ 准备：创建测试仓库"
echo "  主仓库: $TEST_REPO"
echo

BEFORE_COUNT=$(git -C "$TEST_REPO" rev-list --count HEAD)
echo "➤ Before: 主分支 commit = $BEFORE_COUNT"
echo

echo "➤ 执行: 10 个 clean 任务并发"
echo

# Create separate result files for each task
RESULT_DIR=$(mktemp -d)

# Launch 10 clean tasks concurrently
for i in {1..10}; do
  WT="$TEST_REPO/.worktrees/wt-c4-$i"
  git worktree add -q "$WT" -b "wt-c4-$i" HEAD 2>/dev/null

  (
    cd "$WT"
    # Random delay 0-2 seconds to simulate realistic timing
    sleep 0.$((RANDOM % 3))
    set +e
    echo "task $i" | "$CAG_EXEC" mock "$WT" clean >/dev/null 2>&1
    EXIT_CODE=$?
    set -e
    echo "$i:$EXIT_CODE" > "$RESULT_DIR/$i.txt"
  ) &
done

# Wait for all
wait
echo "  (10 个后台任务已完成)"
echo

# Analyze results
echo "➤ 结果分析:"
SUCCESS=0
FAILED=0

for i in {1..10}; do
  if [[ ! -f "$RESULT_DIR/$i.txt" ]]; then
    echo "  ✗ wt$i: 结果文件缺失"
    FAILED=$((FAILED+1))
    continue
  fi

  IFS=: read -r ID EXIT < "$RESULT_DIR/$i.txt"
  BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count "wt-c4-$ID" 2>/dev/null || echo "0")

  if [[ $EXIT -eq 0 && $BRANCH_COUNT -gt $BEFORE_COUNT ]]; then
    SUCCESS=$((SUCCESS+1))
    echo "  ✓ wt$ID: 成功 (exit 0, 有 commit)"
  else
    FAILED=$((FAILED+1))
    echo "  ✗ wt$ID: 失败 (exit $EXIT, commit=$BRANCH_COUNT)"
  fi
done

rm -rf "$RESULT_DIR"
echo

echo "➤ 统计:"
echo "  成功: $SUCCESS/10 ($(($SUCCESS * 100 / 10))%)"
echo "  失败: $FAILED/10"
echo

echo "➤ 验证: 仓库完整性"
git -C "$TEST_REPO" fsck --no-progress >/dev/null 2>&1
FSCK_EXIT=$?
if [[ $FSCK_EXIT -eq 0 ]]; then
  echo "  ✓ git fsck 通过（仓库无损坏）"
else
  echo "  ✗ git fsck 失败（exit $FSCK_EXIT）"
fi
echo

echo "➤ 验证: 主仓库 porcelain 状态"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v " .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净"
else
  echo "  ✗ 工作树有改动:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

echo "➤ 验证: 检查 .git/index.lock 竞争"
if [[ -f "$TEST_REPO/.git/index.lock" ]]; then
  echo "  ✗ index.lock 残留（并发竞争未清理）"
else
  echo "  ✓ 无 index.lock 残留"
fi
echo

echo "➤ C4 结果评估:"
if [[ $SUCCESS -ge 8 && $FSCK_EXIT -eq 0 ]]; then
  echo "  ✅ 通过（≥80% 成功率，仓库完整）"
  echo "    - 成功率: $(($SUCCESS * 100 / 10))%"
  echo "    - git fsck 通过"
  echo "    - 无 lock 残留"
elif [[ $SUCCESS -ge 6 ]]; then
  echo "  ⚠️ 部分通过（60-79% 成功率）"
else
  echo "  ✗ 失败（<60% 成功率或仓库损坏）"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ C4 高并发测试完成"
