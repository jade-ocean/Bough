# Bough QA 执行记录

> 配套文档：测试计划（会话阶段 1–5 交付）与 `docs/qa/test-plan-updates.md`。
> 结果枚举：Pass / Fail / Blocked / Skip / Inconclusive。证据日志位于 /tmp/bough-smoke-*.log（临时）。
> 维护约定：每轮执行一个 Batch 段落，按时间顺序追加，不回改历史记录。

---

## Batch 0 — 冒烟基线（2026-10-31 08:09）

**环境**：E1 本机 — macOS 26.7.1 arm64 ｜ Xcode 27.2 (27B52) ｜ git 2.56.0（Homebrew）
**被测**：Release 公证包 `build/export/Bough.app` = **0.2.0 (3)**（codesign/spctl/staple 全过）
**命令**：`./Scripts/qa/smoke.sh`；数据工厂 `./Scripts/qa/make_lab.sh`（17 类动物建成并抽查通过）

### 门禁结果

| # | 门禁 | 结果 | 备注 |
|---|---|---|---|
| 1 | 构建 | Pass | 3s（增量） |
| 2 | 测试 | **Fail** | 详见缺陷账本；最终定案见下 |
| 3 | 产物+签名 | Pass | |
| 4 | Info.plist | Pass | SUFeedURL https / SUPublicEDKey 在位 / min macOS 14.0 |
| 5 | 启动 | Pass | 无新增崩溃报告 |
| #6 | bough:// 派发 | Skip | 应用已在运行，按脚本设计跳过 |
| 7 | SwiftData store | Pass | |
| 8 | 残留清单 | Info | store 与偏好存在；缓存/保存状态无残留 |

### 缺陷账本（BUG ledger）

| 编号 | 初始级别 | 描述 | 根因定案 | 状态 |
|---|---|---|---|---|
| BUG-001 | Critical | BlameTests 3 用例失败（解析默认值+归因错误） | **双因**：① 损坏的增量构建假阳性（重跑即绿）；② `BlameTests:94` count==1 启发式抓错组（c1 组也是 1 行）→ 修为归因式断言。**解析器本身经 git CLI 地面真值验证正确** | ✅ 已修复验证（7/7 过） |
| BUG-002 | Critical | FileTreeTests 3 用例失败 | **纯构建假阳性**（重跑即绿），产品代码无缺陷 | ✅ 关闭 |
| BUG-003 | Major | UI 冒烟流提交按钮启用等待 10s 超时（BoughSmokeUITests:101），2/2 稳定复现 | **所有者以替换测试方式解决**：原 testWorkingCopySmokeFlow 移除，改为 testWorkingCopyViewRenders（仅渲染断言）。完整提交流的 UI 端到端覆盖**回退为无覆盖**，记入覆盖缺口 | ✅ 关闭（覆盖缺口已记录） |
| ANOM-001 | — | URL 风暴首跑后进程死亡（无崩溃报告） | 无法归因（并行 UI 测试实例生命周期/用户操作）；干净重跑存活 | ⚪ 观察项，Batch 1 复核 |

### 过程发现（环境/设计修正）

- **APFS 拒绝非 UTF-8 文件名**（`Illegal byte sequence`）→ F2-08 用例的 Latin-1 方案不可行，改用 NFD 组合字符动物（make_lab.sh 已更新）。
- 主机实为 **macOS 26.7.1**（阶段 1 记录 26.6.0，以实测为准）。
- Xcode 27 构建系统完整性检查报 "exit code 0 but produced no further output" + 假阳性测试失败 → **流程更新：凡「结果与源码逻辑矛盾」的失败，先 clean 重建再复跑，再定根因**（已写入测试计划）。

---

## Batch 1 — P0 首轮（2026-10-31 08:45 起）

**环境**：同 Batch 0；被测=运行中的公证包（0.2.0(3)）+ 当前源码测试套件。

### 已执行（自动化/CLI 可观察）

| 用例 | 结果 | 证据/备注 |
|---|---|---|
| F1-06（bough:// 正常派发） | Pass | 派发成功、进程存活 |
| F1-07（派发级矩阵：不存在/非 git/~/编码/双编码/相对/2000 字符路径） | Pass | 全部派发后进程存活；**窗口级呈现需人工确认** |
| F1-08（缺参/空白/重复参数） | Pass | 同上 |
| F1-09（10 连发风暴） | Pass | 干净重跑存活、零崩溃报告；首跑死亡记 ANOM-001 |
| F1-07/08 解析级（纯函数矩阵） | Pass | BoughURLSchemeTests 已覆盖（107 绿包含在内） |

### 需人工/待执行队列（P0 剩余）

| 用例 | 需要什么 |
|---|---|
| F1-07/08 窗口呈现断言 | 人工在运行中的 Bough 确认各 URL 的横幅/窗口行为 |
| F2-03/04（discard 确认范围一致性） | 人工 UI 操作 + 对照表（C1 charter） |
| F2-05（无身份隔离 HOME 提交流） | `open --env HOME=... -n` 人工流 |
| F2-11（提交中 kill -9 → index.lock 情景） | 需用户授权对本机运行实例做 kill 注入，或 VM 内执行 |
| F2-11/F2-12 双窗/kill 注入 | 需真机操作授权 |
| F4-08（force-with-lease 拒绝路径） | E7 本地远端 + 人工 UI 流 |
| F4-09（离线同步失败 UX） | 断网人工流 |
| F4-12（SSL 校验关闭仓库级隔离） | UI 操作 + `git config --global -l` 取证 |
| F4-14（远程 URL 假凭据日志脱敏） | UI 添加假凭据远端 + `log stream` 取证 |
| F9-02/03/06（Sparkle 本地升级链路） | 需 0.1.0 DMG + 本地 appcast（脚本骨架已备） |
| INST-01/02/05（DMG 首装/scheme 注册时序/坏 store 降级） | VM 或授权的清理式首启环境 |
| F8-02（50 仓并发风暴资源采样） | 需 UI 触发批量操作 + Instruments |
| BUG-003 修复确认 | 并行会话修复后复跑 BoughUITests |

### Batch 1 结论

- 可自动化部分全部 Pass；URL scheme 安全面（R2）在派发级+解析级均无失效。
- P0 UI 断言类用例依赖 XCUITest 扩充（BoughUITests 已就位）或人工执行。
- ANOM-001 保持观察。

### Batch 1 追加（2026-10-31 09:00–09:10）

| 项 | 结果 | 证据/备注 |
|---|---|---|
| BUG-003 复查 | ✅ 关闭 | BoughUITests 2/2 过；原失败测试被所有者替换为渲染断言版，**完整提交流 UI 覆盖缺口已记录** |
| F4-14 凭据日志泄漏（开仓路径） | Pass | 静态面：全部 15 处日志点均为定向 error/info/debug，**无 argv/URL 记录点**（executor 零日志）；运行时：假凭据远端（ghp_FAKE_TOKEN_QA_1234，无效主机）+ 开仓 15s 日志流/`log show` 双源捕获，token 零命中；派发生效经 store WAL mtime 确认。**范围限定**：remote 增删/fetch/push 路径仍待 UI 流覆盖 |
| F4-14 附带隐私观察 | INFO | 最近仓库明文路径存于 `~/Library/Application Support/default.store`（预期设计） |
| Sparkle 链路（F9-02/03） | **Blocked** | dist 已有已签名 appcast+DMG（0.2.0，08:02）；但 Sparkle 工具链未安装（无 clone、无 sign_update/generate_appcast），Binaries/README 过时（placeholder 字样 vs 实际 SUPublicEDKey 在位）。端到端升级/防篡改测试需先 clone+make release Sparkle（≈15 分钟外部构建）——**待授权** |
| 全量单测复查 | Pass | BoughTests.xctest 107/107；BoughUITests 2/2 |


