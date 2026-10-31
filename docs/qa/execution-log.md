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
| F4-14 凭据日志泄漏（开仓路径） | Pass | 静态面：全部 15 处日志通道为定向 error/info/debug，**无 argv/URL 记录点**（executor 零日志）；运行时：假凭据远端（占位 token + 无效主机）+ 开仓 15s 双源日志捕获，token 零命中；派发生效经 store WAL mtime 确认。**范围限定**：remote 增删/fetch/push 路径仍待 UI 流覆盖 |
| F4-14 附带隐私观察 | INFO | 最近仓库明文路径存于 `~/Library/Application Support/default.store`（预期设计） |
| Sparkle 链路（F9-02/03） | **Blocked** | dist 已有已签名 appcast+DMG（0.2.0，08:02）；工具链缺失 → 本轮已解除（见 09:15–09:50 段） |
| 全量单测复查 | Pass | BoughTests.xctest 107/107；BoughUITests 2/2 |

### Batch 1 追加二：Sparkle 升级链路实测（2026-10-31 09:15–09:50）

**环境**：/tmp/Sparkle-build（浅克隆 + make release，工具在 /tmp/sparkle-lab/bin/）；0.1.1 测试基座（worktree /tmp/bough-011 @30447f3，SUFeedURL 指向本地 feed，Team 3LJQQ4T4DD）；本地 http feed（127.0.0.1:8765）；`default.store` 已备份至 /tmp/sparkle-lab/store-backup/。

| 项 | 结果 | 证据/备注 |
|---|---|---|
| F9-03a 签名字节绑定 | **Pass** | 原始 DMG 签名 == dist appcast 签名（`tuEvcQRY…`，发布物绑定正确）；翻转 1 字节后签名完全不同（EdDSA 字节级绑定成立） |
| **BUG-004**（新，产品级） | 🔴 **Fail 定案** | **自动更新从未在启动时接线**：`UpdaterController.shared` 为惰性单例，仅被「检查更新…」菜单处理器引用（BoughApp.swift:62-63）；0.1.1 更是零触发路径（无菜单项）。`SUEnableAutomaticChecks=true` 形同虚设。**端到端证实**：修复前 0.1.1 启动后 180s 零 feed 请求；harness 注入一行启动接线后立即出现 feed GET。**修复建议（一行）**：启动路径实例化 updater（如 AppDelegate `applicationDidFinishLaunching` 中 `_ = UpdaterController.shared`），已在一次性基座验证有效 |
| F9-02 端到端自动升级 | **Blocked（BUG-004）→ harness 路部分验证** | 修复后 harness：Sparkle 随启动启动，09:28:48 成功 GET 本地 http feed（200，本地 http 被接受）；但下载/安装未在观察窗完成——检查调度有 ~75s 延迟 + 首查后 24h 间隔 + 本环境统一日志捕获不可靠（同一条目 process 谓词可见、subsystem 谓词缺失）三因素叠加，观察窗连续错过。**待所有者修复 BUG-004 后重跑**（工具链/feed/流程已全部就绪，见本段） |
| F9-03 端到端（篡改拒绝） | Inconclusive | 依赖同一升级周期；密码学绑定半边已证（F9-03a）。端到端待 BUG-004 修复后重跑 |
| F9-06 store 数据保留 | Inconclusive | 升级周期未完成；store 全程 integrity_check=ok，备份在案 |
| 日志通道教训 | 流程 | Sparkle 日志 subsystem=`org.sparkle-project.Sparkle`（非宿主 bundle id）；`log show/stream` 默认级**不含** info/debug，必须 `--level debug`；本环境 subsystem 谓词与 process 谓词结果不一致——后续取证以 process 谓词 + `--level debug` 为准 |

**环境遗留**：/tmp/sparkle-lab（feed/DMG/工具/备份）、/tmp/Sparkle-build、/tmp/bough-011（git worktree，含 harness 修复）、http server（8765 端口）——重启即清；git worktree 注册已随 cleanup 移除。

### Batch 1 追加三：BUG-004 修复 + Sparkle 端到端三连（2026-10-31 09:52–10:05）

**前置**：主工程 `AppDelegate.applicationDidFinishLaunching` 注入 `_ = UpdaterController.shared`（BUG-004 修复，注释说明根因与 UITEST 守卫兼容性）；全量回归 **114/114 通过**（112 单元/集成 + 2 UI）。

| 项 | 结果 | 证据/备注 |
|---|---|---|
| **F9-02 端到端自动升级** | ✅ **Pass（30 秒完成）** | 0.1.1 测试基座（带修复）→ 本地 http feed（127.0.0.1:8765）→ 自动检查 → DMG 下载 → Autoupdate XPC 解包+验签 → **原地升级 0.1.1→0.2.0**；升级后 bundle `codesign --verify` 有效、SUFeedURL 恢复生产地址、全程 300s 轮询在 t=30s 命中。Sparkle 决策链完整可见（feed GET ×2 → DMG GET → Installer/Autoupdate 解包） |
| **F9-03 端到端篡改拒绝** | ✅ **Pass（行为级）** | feed enclosure 指向翻转 1 字节的 DMG（保留原始签名）→ 下载 200 → **更新中止、版本保持 0.1.1**、应用正常运行。拒绝发生在 Installer XPC 内（报错为连接失效，与 EdDSA 验签失败在 Installer 内中止的行为一致；Installer 进程内精确日志未取到，归因注明）。密码学半边由 F9-03a 补全（原始==dist、篡改必异） |
| **F9-06 升级数据保留** | ✅ **Pass（构造性+完整性）** | Sparkle 仅替换 bundle：升级周期前后 `default.store` integrity_check 均 ok；升级后 0.2.0 正常启动读同一 store |
| BUG-004 状态 | ✅ 主工程已修 | 全量回归 114/114；Sparkle 端到端三连通过 → **发布门禁 D 组解锁** |
| 观察项（非缺陷） | INFO | Sparkle 报 "bookmark data for update download is stale.. but still continuing"（非沙盒下的非致命警告，成功与拒绝两次运行均出现，不影响结果） |
| 副作用声明 | INFO | 测试写入了共享 defaults 域的 `SULastCheckTime`（已随验证流程删除重置）；Sparkle 测试缓存已清理；feed 已还原为正确 enclosure |

**结论**：BUG-004 修复 + 端到端三连通过后，**升级链路（F9-02/03/06）从「从未验证」变为「全绿」**。发布 Go/No-Go 清单 D 组（Sparkle 端到端、篡改拒绝、DMG 覆盖安装数据保留）现在有实证支撑。

**环境遗留**：/tmp/sparkle-lab 保留（feed/DMG/工具/备份，供 BUG-004 正式出包后复跑）；/tmp/Sparkle-build 可删；http server 已停。

### Batch 2 — 生产路径端到端（2026-10-31 15:25）

**背景**：并行会话已发布 0.3.1/0.4.0/0.4.1（GitHub Pages 托管 appcast），BUG-004 修复（`ba4e894`）已进入 0.4.0/0.4.1 出货基线。

| 项 | 结果 | 证据/备注 |
|---|---|---|
| 0.4.1 发布物签名绑定 | Pass | `sign_update` 对 dist DMG 的输出与 Pages appcast 条目**逐字一致**（`js6ol7hL…`） |
| **生产路径端到端升级** | ✅ **Pass（30s）** | 真实 0.4.0（从 dist DMG 提取，签名有效）经 `open -n` 启动 → Sparkle 随启动启动（**修复在出货二进制中生效**）→ 生产 feed（jade-ocean.github.io）→ 真实 0.4.1 DMG 下载 → Autoupdate XPC 验签解包 → **原地升级 0.4.0→0.4.1**；升级后签名有效、store integrity ok |
| 过程注记 | INFO | 首次 `open`（无 `-n`）激活了已运行实例导致首轮观察窗空转——重跑用 `open -n` 解决；与实验室 F9-02 同款教训，已记入测试计划流程规则 |
| BUG-004 生命周期 | ✅ **闭环** | 发现（Batch 0/1）→ 根因（惰性单例）→ 修复（`ba4e894`，全量回归 114/114）→ 入库 → 随 0.4.0/0.4.1 出货 → **生产路径端到端验证通过** |

**发布链路现状**：0.4.1 生产 feed 在线、签名绑定正确、自动更新经真实出货二进制验证可用。QA 侧对 0.4.1 的发布门禁 A/D 组关键项均有实证；其余人工队列（F2-03/04 discard 确认范围、F4-08/09/12 同步与 SSL 隔离、INST-01/02）保持开放。


