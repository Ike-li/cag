#!/usr/bin/env bash
# test-c5-mixed-concurrency.sh: Band D C5 - Mixed concurrent operations test
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D C5: 混合并发操作测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test C5: Mixed operations (3 clean + 2 escape)
echo "## C5: 混合并发（3 clean + 2 escape）"
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

echo "➤ 执行: 5 个任务并发（3 clean + 2 escape）"
echo "  - wt1: clean"
echo "  - wt2: untracked escape"
echo "  - wt3: clean"
echo "  - wt4: clean"
echo "  - wt5: modified escape"
echo

# Create separate result files for each task
RESULT_DIR=$(mktemp -d)

# Launch 5 tasks with mixed behaviors
for i in 1 2 3 4 5; do
  WT="$TEST_REPO/.worktrees/wt-c5-$i"
  git worktree add -q "$WT" -b "wt-c5-$i" HEAD 2>/dev/null

  # Determine behavior
  case $i in
    1) BEHAVIOR="clean" ;;
    2) BEHAVIOR="untracked" ;;
    3) BEHAVIOR="clean" ;;
    4) BEHAVIOR="clean" ;;
    5) BEHAVIOR="modified" ;;
  esac

  (
    cd "$WT"
    sleep 0.$((RANDOM % 3))
    set +e
    echo "task $i" | "$CAG_EXEC" mock "$WT" "$BEHAVIOR" >/dev/null 2>&1
    EXIT_CODE=$?
    set -e
    # Each task writes to its own file
    echo "$i:$BEHAVIOR:$EXIT_CODE" > "$RESULT_DIR/$i.txt"
  ) &
done

# Wait for all
wait
echo "  (5 个后台任务已完成)"
echo

# Analyze results by reading individual files
echo "➤ 结果分析:"
CLEAN_SUCCESS=0
CLEAN_FAIL=0
ESCAPE_EXIT3=0
ESCAPE_EXIT0=0

for i in 1 2 3 4 5; do
  if [[ ! -f "$RESULT_DIR/$i.txt" ]]; then
    echo "  ✗ wt$i: 结果文件缺失"
    continue
  fi

  IFS=: read -r ID BEH EXIT < "$RESULT_DIR/$i.txt"
  BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count "wt-c5-$ID" 2>/dev/null || echo "0")

  if [[ "$BEH" == "clean" ]]; then
    if [[ $EXIT -eq 0 && $BRANCH_COUNT -gt $BEFORE_COUNT ]]; then
      CLEAN_SUCCESS=$((CLEAN_SUCCESS+1))
      echo "  ✓ wt$ID (clean): 成功 (exit 0, 有 commit)"
    else
      CLEAN_FAIL=$((CLEAN_FAIL+1))
      echo "  ✗ wt$ID (clean): 失败 (exit $EXIT)"
    fi
  else
    if [[ $EXIT -eq 3 ]]; then
      ESCAPE_EXIT3=$((ESCAPE_EXIT3+1))
      echo "  ✓ wt$ID ($BEH): 哨兵拦截 (exit 3)"
    else
      ESCAPE_EXIT0=$((ESCAPE_EXIT0+1))
      echo "  ✗ wt$ID ($BEH): 未拦截 (exit $EXIT)"
    fi
  fi
done

rm -rf "$RESULT_DIR"
echo

echo "➤ 统计:"
echo "  Clean 任务: $CLEAN_SUCCESS/3 成功"
echo "  Escape 任务: $ESCAPE_EXIT3/2 拦截"
echo

echo "➤ 验证: 仓库完整性"
git -C "$TEST_REPO" fsck --no-progress >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  echo "  ✓ git fsck 通过（仓库无损坏）"
else
  echo "  ✗ git fsck 失败（仓库可能损坏）"
fi
echo

echo "➤ 验证: 主仓库 porcelain 状态（应干净）"
PORCELAIN=$(git -C "$TEST_REPO" status --porcelain | grep -v "^?? .worktrees/" || true)
if [[ -z "$PORCELAIN" ]]; then
  echo "  ✓ 工作树干净（escape 被清理）"
else
  echo "  ✗ 工作树有残留:"
  echo "$PORCELAIN" | sed 's/^/    /'
fi
echo

echo "➤ C5 结果评估:"
if [[ $CLEAN_SUCCESS -eq 3 && $ESCAPE_EXIT3 -eq 2 ]]; then
  echo "  ✅ 完美通过（100% 正确性）"
  echo "    - Clean 任务不受影响"
  echo "    - Escape 任务全被拦截"
  echo "    - 无误判、无漏报"
elif [[ $CLEAN_SUCCESS -ge 2 && $ESCAPE_EXIT3 -eq 2 ]]; then
  echo "  ⚠️ 部分通过（Clean 有失败，但 Escape 全拦截）"
else
  echo "  ✗ 失败（Clean 失败或 Escape 漏报）"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ C5 混合并发操作测试完成"
