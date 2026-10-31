# 测试计划增量更新（随 0.2.0 开发演进）

> 本文只记录**增量与修正**；完整计划见会话交付的阶段 1–5（策略/117 用例/自动化/记录规范/Charter）。
> 每次基线变化追加一节，倒序排列，不回改历史。

---

## 更新 1（2026-10-31）：0.2.0(3) 功能面扩充与事实刷新

### 版本与环境事实刷新（覆盖阶段 1「应用信息」）

| 项 | 旧值（阶段 1） | 新值（实测） |
|---|---|---|
| 版本/构建号 | 0.1.1 (2) | **0.2.0 (3)** |
| 主机 macOS | 26.6.0 | **26.7.1** |
| 测试文件 | 14 个 | **19 个**（+Blame/FileTree/HunkStaging/Topology/WorkspaceSafety） |
| UI 自动化 | 无 XCUITest（待确认 Q2） | **BoughUITests 已存在**（2 用例，含 BUG-003） |

### 功能行扩充：F10–F14（加入覆盖矩阵）

| 功能＼维度 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 | D9 | D10 | D11 | D12 | D13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F10 Blame 视图 | P1 | P1 | P1 | — | P1 | — | P1 | — | — | P1 | P1 | P1 | **P0** |
| F11 文件树 Sheet | P1 | P1 | P1 | — | P1 | — | P2 | — | — | P2 | P2 | P1 | **P0** |
| F12 Hunk 级暂存 | **P0** | **P0** | P1 | — | **P0** | — | P2 | P1 | — | P2 | P2 | P1 | **P0** |
| F13 Reflog 找回/安全检出 | **P0** | P1 | P1 | — | P1 | — | — | P1 | — | P2 | P2 | P1 | **P0** |
| F14 并发读写安全 | **P0** | **P0** | P1 | — | — | — | — | P1 | — | — | — | P1 | **P0** |

**新增 P0 聚集区**（矩阵读法）：F12×D1/D2/D5（hunk patch 边界与特殊文件名）、F13×D1（reflog 数据恢复）、F14×D1/D2（写串行最终一致、并发读）。

### 新功能用例（并入用例库，编号续 F10–F14）

| 用例ID | 功能 | 优先级 | 步骤要点 | 预期 | 自动化 |
|---|---|---|---|---|---|
| F12-01 | Hunk 暂存 | P0 | 多 hunk 文件选 1 个 hunk stage | 其余 hunks 保持未暂存；index 与选择一致 | 现有XCTest（testStageOneHunkLeavesRestUnstaged） |
| F12-02 | Hunk 暂存 | P0 | 乱序/非法选择 | PatchBuilder 拒绝非法选择并保持 index 不变 | 现有XCTest（testPatchBuilderRejectsInvalidSelection） |
| F13-01 | Reflog 找回 | P0 | drop 后 reflog 浏览找回丢弃提交 | 丢弃提交经 reflog 可恢复（testReflogBrowseAndRecoverDroppedCommit） | 现有XCTest |
| F13-02 | 安全检出 | P0 | 脏树检出：兼容变更携带/自动 stash/冲突拒绝 | 三分支行为与设计一致（4 个 checkout-safety 集成测试） | 现有XCTest |
| F14-01 | 并发安全 | P0 | 并发读全成功；写串行+最终一致 | WorkspaceSafetyTests 全绿 | 现有XCTest |
| F10-01..04 | Blame | P1 | porcelain 解析/边界/归因/at-ref | BlameTests 全绿（含本次修正的归因断言） | 现有XCTest |
| F11-01..03 | 文件树 | P1 | 树构建/大小/ref 内容 | FileTreeTests 全绿 | 现有XCTest |
| F12-03 | Hunk 暂存 | P1 | submodule/worktree 防护 | HunkStagingTests 中 3 个防护用例 | 现有XCTest |

### 流程规则新增（阶段 3 补充）

- **失败分类前置检查**：凡测试失败结果「与源码逻辑矛盾」（默认值/不可能组合），先 clean 重建 DerivedData 并复跑，排除增量构建假阳性，再进入根因调查。（Batch 0 教训）
- ANOM-001 教训：测试期间进程死亡若**无崩溃报告**且存在并行会话/UI 测试实例，一律先记 Inconclusive，不得归因于被测操作。
