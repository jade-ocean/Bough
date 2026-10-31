# Bough

Every branch starts somewhere.

轻量、原生、快速的 macOS 本地 Git 可视化管理工具。
macOS 14+（SwiftData 最低要求）/ Swift 5 语言模式 / SwiftUI + AppKit 桥接。

## 快速开始

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成：

```bash
brew install xcodegen        # 如未安装
xcodegen generate            # 修改 project.yml 后重新生成 Bough.xcodeproj
open Bough.xcodeproj         # Cmd+R 运行
```

命令行构建与测试：

```bash
xcodebuild -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS' build
xcodebuild test -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS'
```

## 阶段进度

- [x] 阶段 1：工程骨架、三栏布局、打开仓库（.git 探测 / worktree）、bough:// 唤起、最近仓库
- [x] 阶段 2：GitService 封装 + status/stage/unstage/discard + 提交（amend / 签名开关）
- [x] 阶段 3：提交历史图 + 过滤检索 + 提交详情 + diff（内联/并排/高亮/图片）+ 历史右键操作
- [x] 阶段 4：分支管理（列表/新建/删除/重命名/检出/merge/rebase）+ fetch/pull/push + 远程仓库管理
- [x] 阶段 5：三方冲突解决（逐块 ours/theirs/both）+ stash 全生命周期 + tag 管理 + 简化版交互式 rebase
- [x] 阶段 6：搜索（git grep + 提交检索）、快捷键体系、性能优化、release.sh 公证打包 + Sparkle

## 架构边界

- 所有仓库路径 I/O 必须经由 `RepositoryAccessProvider` 协议；
  `RepositoryLocator` 仅作为协议实现内部的基础设施，业务层禁止直接触碰磁盘路径。
- Git 调用全部经 `GitCommandExecutor`（actor，按仓库串行，规避 index.lock 竞争）；
  写操作天然串行，跨仓库互不阻塞。
- 日志：`os.Logger`，subsystem `com.wangyuyang.bough`，Console.app 可按此过滤。

## Git 命令与解析（阶段 2）

| 操作 | 命令 | 解析 |
|---|---|---|
| 状态 | `git status --porcelain=v2 -z --branch --untracked-files=all` | NUL 分隔记录：`#` 分支行、`1` 普通、`2` 重命名（path=新名，NUL 后为旧名）、`u` 冲突、`?` 未跟踪；unborn 判定看 `branch.oid (initial)` |
| 暂存 | `git add -A -- <paths>` | 只看退出码 |
| 取消暂存 | `git restore --staged -- <paths>`，失败（unborn HEAD）回退 `git rm --cached -r -q --` | 只看退出码 |
| 丢弃（已跟踪） | `git checkout HEAD -- <paths>` | 只看退出码；回退到 HEAD，含已暂存内容 |
| 丢弃（未跟踪） | `git clean -f -q -- <paths>` | 只看退出码；UI 必须先弹确认 |
| 提交 | `git commit -m <msg> [--amend] [--gpgsign/--no-gpgsign]` | 成功后 `git rev-parse HEAD` 取新 sha |
| 身份 | `git config --get user.name` / `user.email` | 退出码 1 = 未设置（回退全局配置由 git 自身完成） |
| amend 预填 | `git log -1 --pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%b%x1e` | `\x1f` 分字段、`\x1e` 结束，body 吞并剩余字段 |

执行器细节：`--no-pager` 前缀、`LC_ALL=en_US.UTF-8`、`GIT_OPTIONAL_LOCKS=0`、
路径全部放在 `--` 之后防注入、超时 kill、Task 取消联动 `terminate()`。

## Git 命令与解析（阶段 3）

| 操作 | 命令 | 解析 |
|---|---|---|
| 历史列表 | `git log --topo-order -n 2000 [--all] [--author A] [--grep T -i] [--since D] [--until D] [-- path]` | `%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s%x1e` 记录流；文本过滤走 `--grep`，SHA 前缀客户端过滤 |
| 泳道图 | 纯 Swift `GraphLayouter`（不依赖 `--graph`） | `lanes[i]` 保存各泳道等待的 sha；首父直连、其余父曲线入既有/新泳道；行宽随尾部泳道释放收缩 |
| ref 装饰 | `git for-each-ref --format=%(objectname)%00%(refname)%00%(HEAD)` | refs/heads、refs/remotes、refs/tags 前缀映射为 branch/remote/tag 徽章 |
| 提交文件 | `git diff-tree --no-commit-id --name-status --root -r -M <sha>` + `--numstat` 版 | tab 分列；R/C 带旧路径；numstat 的 `- -` 标记二进制 |
| 文件 diff | `git diff --no-color -U3 <sha>^ <sha> -- path`（根提交用 `git show --format= --root`） | 自研 unified diff 解析：`@@ -a,b +c,d @@` 头、行号跟踪；并排视图按「删块/增块」顺序配对 |
| 工作区 diff | `git diff [--cached] -- path`；未跟踪用 `git diff --no-index -- /dev/null path` | 同上；`--no-index` 的退出码 1 是正常差异，不算失败 |
| 图片预览 | `git show <sha>^:path` / `git show <sha>:path` | NSImage 解码，双版本并排 |
| 检出/回退 | `git checkout -q <sha>`、`git revert --no-edit <sha>`、`git cherry-pick <sha>`、`git reset --<mode> <sha>` | 冲突场景以错误横幅提示，冲突 UI 属阶段 5 |

语法高亮为自研轻量 tokenizer（零依赖）：关键词/字符串/注释/数字 + Markdown 标题围栏引用，
跨行状态（块注释、三引号）按新旧两列独立推进。

## Git 命令与解析（阶段 4）

| 操作 | 命令 | 解析 |
|---|---|---|
| 分支列表 | `git for-each-ref refs/heads --format=%(refname:short)%00%(objectname)%00%(HEAD)%00%(upstream:short)%00%(upstream:track)` | NUL 分列；track 串 `[ahead 1, behind 2]` 正则提取双计数 |
| 远程分支 | `git for-each-ref refs/remotes --format=%(refname:short)%00%(objectname)` | 按远程名分组展示，过滤 HEAD 符号引用 |
| 远程列表 | `git remote -v` | tab 分列，fetch/push URL 去重合并 |
| 新建/删除/重命名 | `git branch <n> [start]` / `git branch -d|-D <n>` / `git branch -m old new` | 名称校验复用 `git check-ref-format --branch` |
| 检出 | `git checkout <branch>` | 远程分支走 DWIM：直接 checkout 短名自动建跟踪分支 |
| 合并/变基 | `git merge --no-edit <b>` / `git rebase <b>`；冲突后 `--abort` / `-c core.editor=true rebase --continue` | 冲突以 status 的 unmerged 条目驱动顶部橙色横幅 |
| 同步 | `git fetch --prune [--all]` / `git pull --no-rebase|--rebase` / `git push [-u origin <b>] [--force-with-lease]` | push 前查 upstream 缺失则补 `-u`；超时放宽到 300s |
| 远程管理 | `git remote add/remove` | SSL 配置写入仓库级 `http.sslVerify` / `http.sslCAInfo` |

## Git 命令与解析（阶段 5）

| 操作 | 命令 | 解析 |
|---|---|---|
| 冲突读取 | `git status` 的 unmerged 条目；工作文件经 RepositoryAccessProvider 读取 | ConflictParser 状态机：`<<<<<<<`/`=======`/`>>>>>>>` 分段，兼容 diff3 的 `|||||||` 基线段 |
| 标记解决 | `git add -- <path>`（回写内容由逐块选择重建，ours/theirs/both） | 外部解决的文件提供「标记为已解决」直通 |
| Stash | `git stash list --pretty=format:%gd%x1f%H%x1f%at%x1f%gs%x1e`、`stash push [-u] -m`、`apply --index` / `pop` / `drop`、`stash show -U3` | reflog 选择器 `stash@{N}` 贯穿操作；patch 复用 DiffParser 渲染 |
| Tag | `for-each-ref refs/tags`（objecttype 区分轻量/附注）、`tag <n>`、`tag -a -m`、`tag -d`、`push <remote> <tag>`、`push <remote> :refs/tags/<n>` | 附注标签 sha 指向 tag 对象 |
| 交互式 rebase | `git rebase -i <base>` + `GIT_SEQUENCE_EDITOR="cp '<临时todo>'"` | Bough 生成 todo（pick/drop/顺序），经临时文件注入，不弹编辑器；支持 keep/drop/重排序/reword（消息经 GIT_EDITOR 队列注入） |

## Git 命令与解析（阶段 6）

| 操作 | 命令 | 解析 |
|---|---|---|
| 代码搜索 | `git grep -n --column -I [-i] [-E\|-F] <pattern> [-- path]` | `file:line:column:text` 冒号分列；退出码 1 = 无匹配（非错误）；500 条截断 |
| 提交检索 | `git log --all -n 100 -i --grep <text> --pretty=<历史格式>` | 复用 GitLogParser.parseHistory；结果可跳转到历史选中 |

| Hunk stage | `git apply --cached --whitespace=nowarn [--reverse]`（stdin patch，DiffParser 重组选中 hunk） | 仅动 index；反向用于部分撤销暂存 |
| Reflog | `git reflog -n 200 --pretty=%H%x1f%h%x1f%at%x1f%gD%x1f%gs` | `HEAD@{n}` 选择器贯穿找回操作 |
| 检出保护 | 失败匹配 `would be overwritten`/`Please commit` → `stash push -u` → checkout → `stash apply`（非 --index） | apply 冲突/modify-delete 时 stash 保留，内容已尽量恢复 |
| 找回建分支 | `git branch <name> <sha>` | sha 来自 reflog 条目 |

## 快捷键

| 快捷键 | 动作 |
|---|---|
| Cmd+O | 打开仓库 |
| Cmd+R | 刷新（状态/分支/stash/tag/历史全量） |
| Cmd+Shift+F | 全局搜索（代码 / 提交） |
| Cmd+1 / Cmd+2 | 历史 / 工作区视图切换 |
| Cmd+Enter | 提交（工作区视图） |
| Cmd+Shift+S | Stash 更改… |
| Cmd+Shift+P | Push |
| Cmd+N / Cmd+T | 新窗口 / 新标签（系统默认） |

**凭据策略**：不实现自有凭据存储。SSH 由系统 ssh-agent 处理，HTTPS 由 git 的
osxkeychain credential helper（macOS 钥匙串）处理——Bough 只调用 git，永不接触密码/token。
远程仓库管理支持企业自建 GitLab 的自定义 URL 与自签证书（CA 路径或显式关闭校验，附风险提示）。

## 签名配置

- `Configs/Signing.xcconfig`：`CODE_SIGN_IDENTITY = Developer ID Application`（Release 公证分发用）。
- **Debug 已覆写为 ad-hoc 签名（`-`）**，本地开发无需任何证书即可运行调试。
- 启用正式签名：在 `Signing.xcconfig` 中取消注释 `DEVELOPMENT_TEAM` 并填入 Team ID。
- 阶段 6 将提供 release.sh 自动化公证打包。

## 发布流程（release.sh + Sparkle）

一次性准备：

```bash
xcrun notarytool store-credentials Bough-notary     # 公证凭据（Apple ID + App-specific password 或 API key）
git clone https://github.com/sparkle-project/Sparkle.git && cd Sparkle && make release
./Binaries/generate_keys.sh                          # EdDSA 签名密钥，公钥填入 Info.plist SUPublicEDKey
```

发布：

```bash
TEAM_ID=你的TeamID ./Scripts/release.sh              # 归档 → Developer ID 导出 → 公证 → staple → DMG → Sparkle 签名片段
TEAM_ID=... NOTARIZE=0 ./Scripts/release.sh          # 本地试跑（跳过公证）
```

然后把 sign_update 输出的签名填进 `Scripts/appcast-sample.xml`，
托管 DMG 与 appcast 到 `SUFeedURL` 指向的服务器即可启用自动更新。

**Info.plist 待办**：把 `SUFeedURL` 换成你的实际 appcast 地址；公证分发前在
`Configs/Signing.xcconfig` 取消 `DEVELOPMENT_TEAM` 注释（release.sh 也可用环境变量注入）。

## 工作区体验包（0.2 迭代）

- [x] **Hunk 级 stage**（P0 #2 收官）：工作区 diff 的 hunk 头部勾选框，
      模式栏「暂存所选 Hunk / 从暂存区撤销所选 Hunk」；底层
      `git apply --cached [--reverse] --whitespace=nowarn`，patch 由
      DiffParser 按选中块重组（header 保留、升序）
- [x] **Reflog 找回**：历史工具栏时钟按钮 → Reflog 面板（HEAD@{n} 操作流），
      右键检出（detached）/ 从此提交新建分支 / 重置当前分支到此处
- [x] **检出保护**：工作区有未提交更改时检出分支弹三选确认
      （自动 Stash 并恢复 / 直接检出 / 取消）；恢复冲突时诚实保留
      stash@{0} 并以横幅提示（与 git 手动流程语义一致）

## 0.3 迭代（设置 / 拓扑 / 性能）

- [x] **设置页**（Bough > 设置…，Cmd+,）：默认 Pull 策略（单点 Pull 菜单与多仓库批量共用）、
      Diff 字号（10–16pt 即时生效）、提交签名默认方式；UserDefaults 持久化（`AppPreferences`）
- [x] **子模块 / Worktree 展示**（P1 #11 收官）：侧栏分区只读列出子模块
      （状态：正常/未初始化/与记录不一致，点击即开子模块仓库）与 linked worktree
      （分支 + 当前标记 + 锁定标记）
- [x] **大仓库历史分页**：首页 500 条，列表尾部「加载更早的提交」增量追加
      （`--skip` 分页，泳道全量重排保持图形正确）
- [x] **executor 读写分离**：写操作仍走每仓库 actor 串行（index.lock 安全），
      读操作（status/log/diff/for-each-ref…）改为无锁并发（`GIT_OPTIONAL_LOCKS=0`）；
      刷新链路（状态/分支/stash/标签/历史）并发执行。过程中修复了 actor
      `await` 重入导致的并发写 index.lock 竞态（执行器内加续体 gate 真串行）

## Roadmap（后续方向）

- [x] 多仓库批量操作（P2 #16）：独立总览窗口（Cmd+Shift+M），并发扫描分支/ahead-behind/脏文件数，
      批量 Fetch、批量 Pull（merge，带确认）；核心逻辑 TaskGroup 并发，单仓失败不阻断批次
- [x] 交互式 rebase 的 reword 支持：todo 注入 `reword` 行，新信息经 GIT_EDITOR 消息队列
      按序消费（仍不弹编辑器）；Sheet 中每步可标记改写并输入新信息
- [x] 冲突视图行内编辑增强：逐行勾选 ours/theirs（行级优先于整块选择）、diff3 基线参考列
- [x] 真分层图标源：`Scripts/make_appicon_layers.swift` 产出 background/foreground/foreground-mono
      三个 SVG 图层（与主图标同坐标系），Icon Composer 导入即可生成 `.icon`
- [ ] appcast 托管上线：dist 包已就绪（`build/dist/`：DMG + appcast.xml + UPLOAD.md 托管说明），
      待确定托管地址后改 SUFeedURL 重出包
- [ ] 真分层 Liquid Glass 图标：三图层 SVG 已就绪（`build/icon-layers/`），待 Icon Composer 手工组装

### 0.4 迭代（blame / 文件树 / XCUITest 冒烟）

- [x] **Blame 视图**：diff 模式栏按钮切换逐行作者/日期/SHA（sha 稳定配色），
      工作区文件按 HEAD、提交文件按该提交 blame（`git blame --porcelain --root -w`）
- [x] **文件树浏览**：历史右键「浏览此提交的文件树…」→ OutlineGroup 树 + 内容查看
      （语法高亮 / 图片预览 / 二进制识别 / 另存为），`git ls-tree -r -l` 构建层级
- [x] **XCUITest 冒烟**：BoughUITests target（runner 关沙盒跑 git seed）；
      启动钩子 `UITEST_REPO_PATH` / `UITEST_VIEW`（DEBUG 限定），UI 测试自动跳过
      Sparkle。覆盖：开仓→历史渲染、工作区三面板+脏文件行+批量操作、欢迎页。
      已知限制：XCUITest 驱动 SwiftUI Button/TextEditor 交互（按钮 action 不递送、
      AX 状态回弹）不可靠，stage/commit 端到端由 100+ 单元/集成测试覆盖
- [x] 附带修复：blame fixture 39 位 sha、ls-tree 对齐空格解析、buildTree 值语义

### 0.5 迭代（联动 + 懒加载）

- [x] **Blame↔历史联动**：blame 行内短 SHA 可点击（下划线提示），点击即
      切换到历史视图并在详情选中该提交（`commitBody` 拉取元数据；
      无效 SHA 走错误横幅）。历史列表行可见时同步高亮（不滚动定位）
- [x] **文件树懒加载**：文件树 Sheet 改为按需加载——首次只拉顶层
      （`git ls-tree -l <ref>`），目录展开时逐层加载（`-- <prefix>/`），
      路径寻址的不可变更新拼接子层（`GitTreeParser.updateChildren`）；
      `TreeNode.childrenLoaded` 区分「未加载 / 已加载空目录」；超大仓库
      打开文件树不再全量递归
- [x] 已知波动：全量并行测试偶发 suite 间 flake（git 进程风暴下个别
      命令失败），单独/复跑均绿——后续给集成测试加无效化重试或关并行

## 应用图标

## 应用图标

设计源：`Scripts/make_appicon.swift`（CoreGraphics 矢量绘制，单一事实源）。
概念：向上生长的 Y 形大枝 + 枝端 commit 节点（呼应历史泳道图），
暖纸渐变底（不透明背景层）+ 清晰边缘前景层，核心内容居中 80% 安全区，
系统自动套 Liquid Glass 圆角遮罩（不预画圆角）。

```bash
xcrun swift Scripts/make_appicon.swift   # 重新生成 10 尺寸 appiconset + build/icon-preview/
```

已知坑：本机 Xcode 27 的 actool 对 macOS **单尺寸** appiconset 会静默跳过
（car 里不出现图标且无报错），必须使用经典 10 尺寸格式（16→1024 含 @2x）。
做真分层 Liquid Glass `.icon`（深色/单色变体）时，用 Icon Composer 打开
`build/icon-preview/icon_1024.png` 分层重建即可。

## bough:// URL Scheme 测试

```bash
open "bough://open?path=/Users/你的用户名/某个仓库路径"
open "bough://open?path=~/code/my-repo"   # 支持 ~ 展开
```

首次需先运行过 Bough，LaunchServices 才会注册 scheme；失败时检查
`/System/Applications` 无关，直接用上面的命令验证即可。

## 手动验收清单

### 阶段 1
- [ ] 启动后显示欢迎页（品牌视觉 + 最近仓库）
- [ ] Cmd+O / 欢迎页按钮 → NSOpenPanel 选目录 → 非 git 目录给出错误横幅
- [ ] 选择子目录也能定位到仓库根（对齐 `git rev-parse --show-toplevel` 语义）
- [ ] 拖拽文件夹到窗口 → 打开对应仓库
- [ ] 打开 worktree 仓库（.git 为文件形态）正常
- [ ] 最近仓库出现在欢迎页与侧栏；点击打开；右键可移除
- [ ] `open "bough://open?path=..."` 唤起打开仓库
- [ ] 底部状态栏显示仓库路径与操作状态；左栏占位树展示「即将支持」

### 阶段 2
- [ ] 打开仓库后中栏出现「已暂存 / 未暂存 / 未跟踪」三列表，空仓库显示「工作区干净」类空态
- [ ] 修改/新建/删除文件后 Cmd+R 刷新列表；状态图标与颜色正确（绿+ / 橙改 / 红删 / 蓝重命名 / 灰未跟踪）
- [ ] 单文件与「全部暂存 / 全部取消暂存」批量操作生效
- [ ] 丢弃已跟踪更改、删除未跟踪文件均有二次确认 sheet（列出受影响文件）
- [ ] 勾选身份后提交：未配置 user.name/email 时按钮禁用并显示橙色提示
- [ ] Cmd+Enter 提交成功后列表清空、状态栏分支正常
- [ ] 「修改上次提交」勾选后自动预填上次信息；amend 后 sha 变化
- [ ] 签名 Picker 三档（跟随配置 / 不签名 / 签名）传参正确
- [ ] 底部状态栏实时显示分支与 ↑ahead ↓behind

### 阶段 3
- [ ] 中栏默认历史图：泳道分叉/合并曲线正确，HEAD 提交有高亮圈，分支/tag/远程徽章显示
- [ ] 工具栏「历史 | 工作区」分段切换记忆当前视图；「图形」开关可折叠为纯列表
- [ ] 过滤栏：消息/SHA 文本、作者下拉、路径前缀、起止日期组合过滤即时生效
- [ ] 点击提交 → 右栏显示提交头（标题/正文/作者/日期/SHA/复制按钮）+ 文件列表 + diff
- [ ] diff 支持内联/并排切换；语法高亮对 Swift/JS/TS/Python/Go/Rust/Markdown 生效
- [ ] 工作区列表点击文件 → 右栏直接看该文件 diff（已暂存/未暂存/未跟踪语义正确）
- [ ] 图片文件显示双版本预览；二进制文件显示提示；超大 diff 截断到 5000 行
- [ ] 历史行右键：复制 SHA / 检出（detached）/ cherry-pick / revert / 重置（三模式确认单）
- [ ] reset hard 有不可撤销警示；revert 成功后历史自动刷新出现新提交

### 阶段 4
- [ ] 侧栏「分支」列出本地分支：当前分支加粗勾选、上游 ↑ahead ↓behind 徽章
- [ ] 新建分支（可选起点 + 立即检出）、重命名、删除（安全/强制双确认）、检出、合并、Rebase
- [ ] 分支名非法时给出横幅提示（空格、`..` 等被 git check-ref-format 拒绝）
- [ ] 「远程分支」按远程分组；右键可检出到本地跟踪分支
- [ ] 「远程仓库」增删改：URL 编辑、自签 CA 路径或关闭 SSL 校验（带风险提示）
- [ ] 工具栏同步菜单：Fetch 全部 / Pull（merge|rebase 策略）/ Push / force-with-lease
- [ ] pull/push 后分支徽章与状态栏 ahead/behind 即时刷新
- [ ] 冲突场景：顶部橙色横幅出现冲突计数 + 继续 Rebase / 中止 Rebase / 中止 Merge
- [ ] SSH 推拉走系统 ssh-agent 免密；HTTPS 走钥匙串，全程无需在 Bough 里输入凭据

### 阶段 5
- [ ] 制造冲突后顶部橙色横幅出现，点「解决冲突…」打开三方解决界面
- [ ] 逐块选择 ours/theirs/both，按钮高亮、块底色随状态变化；进度 x/y 实时更新
- [ ] 全部选择后「保存并标记已解决」可点，回写后文件从冲突列表消失、unmerged 清零
- [ ] 外部编辑器解决后可用「标记为已解决（外部编辑）」直通
- [ ] 侧栏 Stash 分区：+ 暂存当前更改（含未跟踪开关）；点击条目右栏查看 patch
- [ ] Stash 应用/弹出/删除均即时刷新列表；stash 详情页有应用/弹出快捷按钮
- [ ] 侧栏标签分区：+ 新建（轻量/附注切换）；右键推送/删除；历史图行上出现标签徽章
- [ ] 历史右键「在此提交上打标签…」预填目标提交
- [ ] 历史右键「交互式 Rebase（简化版）…」：提交列表可排序/标记丢弃，执行后历史重写
- [ ] reset hard 有不可撤销警示；revert 成功后历史自动刷新出现新提交
