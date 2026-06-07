# CAG 智能模型选择指南

主 Claude 根据任务特征自动选择 provider、model 和 reasoning effort。

**⚠️ 重要限制**：
- **codex 仅支持 gpt-5.5**（ChatGPT 账号限制）
- **传递 gpt-4o 或 o3 会快速失败**（cag-exec 预检查）
- **建议：不传 MODEL 参数**，让 codex 使用默认 gpt-5.5
- **agy 不支持 REASONING 参数**，只能通过 model 选择控制

---

## 决策矩阵

### Provider 选择

| 任务类型 | Provider | 原因 |
|---------|----------|------|
| 逻辑/算法/测试 | codex | OpenAI 模型逻辑严密，测试覆盖好 |
| 重构/安全审查 | codex | 代码理解能力强，边界情况考虑周全 |
| 文档生成 | agy | Gemini 大上下文，文档写作流畅 |
| 多文件概览 | agy | Gemini 2M context，全局视角好 |
| UI/UX/样式 | agy | 视觉和可读性优化能力强 |

---

## Model 选择

### Codex (OpenAI)

**重要**：当前 codex 使用 ChatGPT 账号，仅支持 `gpt-5.5` 模型。

| 模型 | 适用场景 | 速度 | 成本 | 可用性 |
|------|---------|------|------|--------|
| **gpt-5.5** (默认) | 通用平衡：重构、文档、测试 | 中 | 中 | ✅ 可用 |
| **o3** | 复杂算法、数学推理、架构设计 | 慢 | 高 | ❌ ChatGPT 账号不支持 |
| **gpt-4o** | 简单改动、快速原型 | 快 | 低 | ❌ ChatGPT 账号不支持 |

**建议**：
- 目前所有任务使用 gpt-5.5（不传 model 参数）
- 通过 reasoning effort 控制复杂度（low/medium/high/xhigh）
- 如需使用其他模型，需要升级到 OpenAI API 账号

### Agy (Gemini)

**实际可用模型**（通过 agy CLI 验证）：

| 模型 | 适用场景 | 速度 | 推荐 |
|------|---------|------|------|
| **Gemini 3.5 Flash (Medium)** (默认) | 通用文档、多文件编辑 | 快 | ✅ 默认使用 |
| **Gemini 3.5 Flash (High)** | 需要更高质量的文档任务 | 中 | 复杂文档 |
| **Gemini 3.5 Flash (Low)** | 简单格式化、机械编辑 | 最快 | 简单任务 |
| **Gemini 3.1 Pro (Low)** | 大上下文文档（速度优先） | 中 | 大文档 |
| **Gemini 3.1 Pro (High)** | 大上下文文档（质量优先） | 慢 | 复杂大文档 |
| **Gemini 3 Flash** | 轻量级快速任务 | 快 | 快速原型 |

**注意**：
- agy 不支持 reasoning-effort 参数
- 通过选择不同模型控制质量和速度
- 模型名称需要精确匹配（包括大小写和括号）

---

## Reasoning Effort 选择

| 级别 | 适用场景 | 特征 |
|------|---------|------|
| **low** | 简单重命名、格式化、复制粘贴 | 快速，低成本 |
| **medium** (默认) | 常规开发任务：添加功能、修复 bug | 平衡 |
| **high** | 复杂重构、多步推理、需考虑边界情况 | 更深思考 |
| **xhigh** | 算法设计、安全审查、架构决策 | 最深推理 |

---

## 决策流程（主 Claude 执行）

```
1. 分析任务特征
   - 任务类型：逻辑？文档？重构？
   - 复杂度：简单？中等？复杂？
   - 文件数量：单文件？多文件？
   - 上下文需求：小？大？

2. 选择 Provider
   if 逻辑/测试/安全:
     provider = codex
   elif 文档/大上下文/UI:
     provider = agy

3. 选择 Model
   if provider == codex:
     # 当前 codex 使用 ChatGPT 账号，仅支持 gpt-5.5
     # 建议：不指定 model 参数，使用默认配置
     model = (留空)  # 使用默认 gpt-5.5
   elif provider == agy:
     if 大上下文:
       model = "Gemini 3.1 Pro (Low)"  # 或 "Gemini 3.1 Pro (High)"
     elif 简单任务:
       model = "Gemini 3.5 Flash (Low)"
     elif 复杂文档:
       model = "Gemini 3.5 Flash (High)"
     else:
       model = (留空)  # 使用默认 Gemini 3.5 Flash (Medium)

4. 选择 Reasoning（codex only，agy 不支持）
   if 简单重复劳动:
     reasoning = low
   elif 复杂推理/安全/架构:
     reasoning = xhigh
   else:
     reasoning = medium  # 默认
```

---

## 示例

### 示例 1：简单格式化

**任务**：统一所有文件的缩进为 2 空格

**决策**：
- Provider: codex（代码格式化）
- Model: （不指定，使用默认 gpt-5.5）
- Reasoning: low（无需深度思考）

**Agent prompt 包含**：
```
MODEL: 
REASONING: low
```

---

### 示例 2：算法优化

**任务**：优化排序算法，降低时间复杂度

**决策**：
- Provider: codex（算法逻辑）
- Model: （不指定，使用默认 gpt-5.5）
- Reasoning: xhigh（需要深度分析）

**Agent prompt 包含**：
```
MODEL: 
REASONING: xhigh
```

---

### 示例 3：多文件文档生成

**任务**：为整个项目生成 API 文档

**决策**：
- Provider: agy（文档 + 大上下文）
- Model: Gemini 3.1 Pro (Low)（大上下文）
- Reasoning: （不支持）

**Agent prompt 包含**：
```
MODEL: Gemini 3.1 Pro (Low)
REASONING: 
```

---

### 示例 4：常规 bug 修复

**任务**：修复登录页面的验证 bug

**决策**：
- Provider: codex（逻辑修复）
- Model: （留空，用默认 gpt-5.5）
- Reasoning: medium（标准调试）

**Agent prompt 包含**：
```
MODEL: 
REASONING: medium
```

---

## 在 Agent Prompt 中传递

主 Claude 在派发 delegate 时，将模型参数加入 prompt：

```
Agent(
  subagent_type="codex-delegate",
  prompt="""
TASK_ID: optimize-sort
WORKTREE: /path/to/worktree
ARTIFACT: /path/to/artifact.md
MODEL: 
REASONING: xhigh
SUBTASK:
优化 src/sort.js 中的排序算法...
ACCEPTANCE:
- 时间复杂度 O(n log n)
- 通过所有测试
"""
)
```

Delegate 会将 `MODEL` 和 `REASONING` 传递给 `cag-exec`。

**注意**：
- MODEL 留空时使用 provider 默认配置
- codex 当前只支持 gpt-5.5，建议总是留空
- agy 不支持 REASONING 参数

---

## 成本优化建议

**当前环境**（codex 使用 ChatGPT 账号）：

1. **codex 任务：通过 reasoning effort 控制复杂度**
   - 简单任务：`REASONING: low`
   - 常规任务：`REASONING: medium`（默认）
   - 复杂任务：`REASONING: xhigh`
   - MODEL 总是留空（使用默认 gpt-5.5）

2. **agy 任务：通过 model 选择控制**
   - 大上下文文档：`MODEL: Gemini 3.1 Pro (Low)` 或 `Gemini 3.1 Pro (High)`
   - 简单任务：`MODEL: Gemini 3.5 Flash (Low)`
   - 复杂文档：`MODEL: Gemini 3.5 Flash (High)`
   - 其他任务：MODEL 留空（使用默认 Gemini 3.5 Flash (Medium)）
   - 不传递 REASONING（agy 不支持）

3. **默认策略**
   - 大部分任务不传 MODEL 参数
   - codex 任务根据复杂度调整 REASONING
   - agy 任务根据需求选择合适的 Gemini 模型

---

## 验证

```bash
# 查看实际使用的模型（从 artifact 中）
cat /path/to/artifact.md | grep -E "(model|OpenAI|Gemini)"
```
