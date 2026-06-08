#!/usr/bin/env bash
# test-c1-c3-concurrency.sh: Band D C1-C3 - Concurrency stress tests
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CAG_EXEC="$SCRIPT_DIR/../../bin/cag-exec"

echo "════════════════════════════════════════════════════════════════"
echo "  Band D C1-C3: 并发压力测试"
echo "════════════════════════════════════════════════════════════════"
echo

# Test C1: Serial baseline (5 tasks)
echo "## C1: 串行基线（5 个任务）"
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

echo "➤ 执行: 5 个任务串行"
SUCCESS=0
FAIL=0
for i in $(seq 1 5); do
  WT="$TEST_REPO/.worktrees/wt-c1-$i"
  git worktree add -q "$WT" -b "wt-c1-$i" HEAD 2>/dev/null || { echo "  ✗ worktree $i 创建失败"; FAIL=$((FAIL+1)); continue; }

  cd "$WT"
  RESULT=$(echo "task $i" | "$CAG_EXEC" mock "$WT" clean 2>&1)
  EXIT_CODE=$?

  if [[ $EXIT_CODE -eq 0 ]]; then
    # Verify the branch has new commits
    BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count "wt-c1-$i")
    if [[ $BRANCH_COUNT -gt $BEFORE_COUNT ]]; then
      SUCCESS=$((SUCCESS+1))
      echo "  ✓ Task $i 成功（分支有新 commit）"
    else
      FAIL=$((FAIL+1))
      echo "  ✗ Task $i exit 0 但无 commit"
    fi
  else
    FAIL=$((FAIL+1))
    echo "  ✗ Task $i 失败 (exit $EXIT_CODE)"
  fi
done

echo
echo "➤ 结果: $SUCCESS/5 成功"
if [[ $SUCCESS -eq 5 ]]; then
  echo "  ✓ C1 通过（100% 成功率）"
else
  echo "  ✗ C1 失败（$FAIL 个任务失败）"
fi
echo

# Verify git fsck
git -C "$TEST_REPO" fsck --no-progress >/dev/null 2>&1
echo "➤ 仓库完整性: ✓ git fsck 通过"
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test C2: Low concurrency (2 parallel)
echo "## C2: 低并发（2 个并行）"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"

echo "✓ 准备：创建测试仓库"
echo

BEFORE_COUNT=$(git -C "$TEST_REPO" rev-list --count HEAD)
echo "➤ Before: 主分支 commit = $BEFORE_COUNT"
echo

echo "➤ 执行: 2 个任务并行"
RESULT_FILE=$(mktemp)

# Launch 2 tasks in background
for i in 1 2; do
  WT="$TEST_REPO/.worktrees/wt-c2-$i"
  git worktree add -q "$WT" -b "wt-c2-$i" HEAD 2>/dev/null

  (
    cd "$WT"
    echo "task $i" | "$CAG_EXEC" mock "$WT" clean >/dev/null 2>&1
    EXIT_CODE=$?
    echo "$i:$EXIT_CODE" >> "$RESULT_FILE"
  ) &
done

# Wait for all background jobs
wait

echo "  (2 个后台任务已完成)"
echo

# Count successes
SUCCESS=0
FAIL=0
for i in 1 2; do
  BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count "wt-c2-$i" 2>/dev/null || echo "0")
  if [[ $BRANCH_COUNT -gt $BEFORE_COUNT ]]; then
    SUCCESS=$((SUCCESS+1))
    echo "  ✓ Task $i 成功（分支有新 commit）"
  else
    FAIL=$((FAIL+1))
    echo "  ✗ Task $i 失败或无 commit"
  fi
done

rm -f "$RESULT_FILE"
echo

echo "➤ 结果: $SUCCESS/2 成功"
if [[ $SUCCESS -eq 2 ]]; then
  echo "  ✓ C2 通过（100% 成功率）"
else
  echo "  ⚠ C2 部分成功（$SUCCESS/2）"
fi
echo

git -C "$TEST_REPO" fsck --no-progress >/dev/null 2>&1
echo "➤ 仓库完整性: ✓ git fsck 通过"
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo

# Test C3: Medium concurrency (5 parallel)
echo "## C3: 中并发（5 个并行）"
echo "---"
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO" && git init -q && git config user.name t && git config user.email t@t
echo "init" > init.txt && git add -A && git commit -qm "init"

echo "✓ 准备：创建测试仓库"
echo

BEFORE_COUNT=$(git -C "$TEST_REPO" rev-list --count HEAD)
echo "➤ Before: 主分支 commit = $BEFORE_COUNT"
echo

echo "➤ 执行: 5 个任务并行（可能有 .git/index.lock 竞争）"

# Launch 5 tasks in background
for i in 1 2 3 4 5; do
  WT="$TEST_REPO/.worktrees/wt-c3-$i"
  git worktree add -q "$WT" -b "wt-c3-$i" HEAD 2>/dev/null

  (
    cd "$WT"
    # Add small random delay to reduce lock contention
    sleep 0.$((RANDOM % 3))
    echo "task $i" | "$CAG_EXEC" mock "$WT" clean >/dev/null 2>&1
  ) &
done

# Wait for all
wait
echo "  (5 个后台任务已完成)"
echo

# Count successes by checking each branch
SUCCESS=0
FAIL=0
for i in 1 2 3 4 5; do
  BRANCH_COUNT=$(git -C "$TEST_REPO" rev-list --count "wt-c3-$i" 2>/dev/null || echo "0")
  if [[ $BRANCH_COUNT -gt $BEFORE_COUNT ]]; then
    SUCCESS=$((SUCCESS+1))
    echo "  ✓ Task $i 成功"
  else
    FAIL=$((FAIL+1))
    echo "  ✗ Task $i 失败或无 commit"
  fi
done

echo

echo "➤ 验证: 仓库完整性"
git -C "$TEST_REPO" fsck --no-progress >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  echo "  ✓ git fsck 通过（仓库无损坏）"
else
  echo "  ✗ git fsck 失败（仓库可能损坏）"
fi
echo

SUCCESS_RATE=$((SUCCESS * 100 / 5))
echo "➤ 结果: $SUCCESS/5 成功（$SUCCESS_RATE%）"
if [[ $SUCCESS -ge 4 ]]; then
  echo "  ✓ C3 通过（≥80% 成功率）"
else
  echo "  ✗ C3 失败（<80% 成功率）"
fi
echo

cd /tmp && rm -rf "$TEST_REPO"
echo "════════════════════════════════════════════════════════════════"
echo
echo "✓ C1-C3 并发压力测试完成"
