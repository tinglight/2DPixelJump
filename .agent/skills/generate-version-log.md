---
name: generate-version-log
description: >-
  Generates player-friendly release notes from Git history for the 2D
  platformer project. Use when the user asks for version logs, changelog,
  版本更新日志, generate-version-log, or after a 版本号更新 commit.
disable-model-invocation: true
---

# 生成版本更新日志（Git）

为 **2D横板跳跃** 生成玩家友好的版本更新日志。版本号以仓库根目录 `VERSION` 为准；日志输出到 `VersionLog/`。

## 运行模式

1. **批量模式（默认）**：无参数 → 生成所有缺失版本的日志
2. **指定版本**：`0.0.2` → 只生成该版本
3. **最新版本**：`latest` → 只生成当前 `VERSION` 对应版本（若缺失）

参数映射：用户消息中的版本号 / `all` / `latest` 即上述模式。

## 版本号约定

- 格式：语义化版本 `MAJOR.MINOR.PATCH`（如 `0.0.1`），可选后缀（如 `0.1.0-beta`）
- 权威来源：根目录 `VERSION`（单行，无空格）
- 发布时同步 `project.godot` 的 `config/version`
- **版本号更新提交** 信息格式（必须一致，便于检索）：

```
版本号更新: {旧版本} -> {新版本}
```

示例：`版本号更新: 0.0.1 -> 0.0.2`。首次建立版本可用：`版本号更新:  -> 0.0.1`

## 执行步骤

### 0. 同步远程

```powershell
Set-Location "<仓库根目录>"
git pull
```

### 1. 扫描已有日志

检查 `VersionLog/`：
- 已生成：`{版本号}.md` 或 `{版本号}_draft.md`
- 提取已有版本号列表

### 2. 获取版本更新记录

```powershell
git log -500 --format="%H|%an|%ad|%s" --date=short | Out-File -FilePath "VersionLog/temp_version_search.txt" -Encoding utf8
```

解析所有包含 `版本号更新:` 的提交，构建：

```
版本号 | 该次更新的 commit hash | 上一次版本更新的 commit hash
```

### 3. 确定待生成列表

- Git 中有版本更新记录、`VersionLog/` 中无对应 `.md` / `_draft.md` → 待生成
- 参数：`all` 或空 → 全部缺失；`latest` → 仅 `VERSION` 文件中的版本；具体版本号 → 仅该版

### 4. 按版本从旧到新逐个生成

#### 4.1 计算 Git 提交范围

版本日志包含：**上一版版本号更新之后** 到 **当前版本号更新之前** 的所有提交（不含两次「版本号更新」提交本身）。

设：
- `PREV` = 上一版 `版本号更新` 的 commit
- `CURR` = 当前版 `版本号更新` 的 commit

```powershell
# 有上一版时
git log --format="%H|%an|%ad|%s" --date=short PREV..CURR^
```

**无上一版**（如首个 `0.0.1`）：使用 `CURR` 之前的全部提交：

```powershell
git log --format="%H|%an|%ad|%s" --date=short CURR^
```

**常见错误**：
- ❌ 包含 `CURR` 或之后的提交
- ❌ 包含 `PREV` 本身
- ✅ 范围等价于 SVN 的 `(prev_rev+1)..(curr_rev-1)`

#### 4.2 收集日志

推荐写入文件再 Read，避免终端编码问题：

```powershell
git log --format="%h|%an|%ad|%s" --date=short PREV..CURR^ | Out-File -FilePath "VersionLog/temp_log.txt" -Encoding utf8
```

#### 4.3 保存原始日志

`VersionLog/{版本号}_raw.txt`：

```
abc1234 | author | 2026-05-27 | 提交说明
...
```

#### 4.4 润色规则

**分类**：新功能 | 修复 | 优化 | 平衡性调整 | 音频 | 美术

**过滤**：纯内部改动（重构、调试、维护）、空 message、可合并的同类项

**表述**：玩家可读；修复「修复了…」；功能「新增/添加…」；优化「优化/改进了…」

#### 4.5 保存草稿

`VersionLog/{版本号}_draft.md`：

```markdown
# 版本 {版本号} 更新日志

> 发布日期：{日期}
> Git 范围：{起始短 hash} .. {结束短 hash}
> 提交数量：{n} 次

## 新功能
- ...

## 修复
- ...

---

*此日志由 Agent 自动生成，审核后将 `_draft.md` 重命名为 `{版本号}.md`*
```

无内容的分类不展示；无法归类条目放在 **待确认**。

### 5. 输出结果

汇总表格：版本号 | Git 范围 | 提交数 | 文件名，并提醒审核草稿。

### 6. 生成本次 Skill 运行报告（必须）

每次执行本 skill 结束时，**必须**生成一份运行报告并纳入 Git 提交（与步骤 7 一并完成，不得遗漏）。

**路径**：`VersionLog/reports/{版本号或 batch}_{YYYYMMDD-HHmmss}_report.md`

- 单版本：`0.0.2_20260527-143052_report.md`
- 批量：`batch_20260527-143052_report.md`

**报告模板**：

```markdown
# Skill 运行报告

> 执行时间：{ISO 本地时间}
> 运行模式：{批量 | latest | 指定版本}
> 当前 VERSION：{读取 VERSION 文件}

## 生成结果

| 版本号 | Git 范围 | 提交数 | 输出文件 | 状态 |
|--------|----------|--------|----------|------|
| ... | abc..def | n | 0.0.2_draft.md | 待审核 |

## 本次写入的文件

- VersionLog/...
- （列出所有新建/修改路径）

## Git 提交（本 skill 触发）

- **将提交的文件**：{列表}
- **计划 commit message**：`chore(version-log): skill 报告与版本日志 {版本列表}`
- **commit hash**：（步骤 7 提交后填写；版本号锚点提交填实际 hash，本报告提交写「本提交（`git log -1 --format=%h`）」）

## 备注

{异常、待确认项、需人工审核的草稿}
```

报告中的「Git 提交」小节在 `git commit` 成功后补充实际 **commit hash**。

### 7. 提交到 Git（必须）

本 skill **每次调用结束时**必须执行一次 Git 提交，包含：

1. 本次生成的版本日志（`*_draft.md`、`*_raw.txt`、已审核的 `*.md`）
2. **本次运行报告**（`VersionLog/reports/*_report.md`）
3. 若因完善流程修改了 `SKILL.md`，一并提交

**不纳入**本次自动提交：`VERSION`、`project.godot` 的版本号更新（属「发布新版本」单独提交，见下文）。

```powershell
Set-Location "<仓库根目录>"
git add VersionLog/
git status
git commit -m "chore(version-log): skill 报告与版本日志 {版本列表}"
```

- `{版本列表}`：如 `0.0.2` 或 `0.0.1,0.0.2`（批量用逗号分隔）
- 若无新草稿仅生成报告：message 仍为 `chore(version-log): skill 运行报告`
- 提交成功后，在「Git 提交」小节填入 **commit hash**；其中「本 skill 报告提交」可写 `git log -1 --format=%h` 的结果，**勿为回写 hash 反复 amend**（避免 hash 与报告内容循环变化）

完成后向用户展示：commit hash、已提交文件列表、报告路径。

## 发布新版本（人工或 Agent 协助）

1. 完成本版本功能开发并提交
2. 更新 `VERSION` 与 `project.godot` 的 `config/version`
3. 单独提交：`版本号更新: 0.0.1 -> 0.0.2`
4. 运行本 skill 生成 `VersionLog/0.0.2_draft.md`

## 特殊情况

- 找不到上一版 `版本号更新`：按「无上一版」处理，或询问用户指定起始 commit
- `git` 失败：提示检查 Git 环境与仓库路径
- 范围内无玩家可见提交：写「本版本无玩家可见更新」
- 版本号含后缀时，文件名与匹配均含后缀

## 示例

```
generate-version-log           # 批量
generate-version-log all
generate-version-log latest
generate-version-log 0.0.2
```
