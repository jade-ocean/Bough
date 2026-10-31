# Bough 发版手册

> 目标读者：维护者（王玉洋）。本文是**唯一权威发版流程**，按顺序照做即可。
> 最后验证于 0.4.0（2026-10-31，全链路含 GitHub Pages 自动更新源）。

## 一页速查

```bash
# 0. 提交 + 全量测试（串行，约 30s，必须全绿）
git add -A && git commit -m "feat: ..."
xcodebuild test -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS'

# 1. 改版本号（Configs/Base.xcconfig 两行），提交
#    MARKETING_VERSION = 0.X.Y   ← 用户可见版本（semver）
#    CURRENT_PROJECT_VERSION = N ← build 号，永远 +1，绝不复用/回退

# 2. 归档 + 公证 + DMG（后台约 5 分钟）
TEAM_ID=3LJQQ4T4DD ./Scripts/release.sh

# 3. 签名新 DMG，把输出填进 Scripts/appcast-sample.xml（新增 item，见下）
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update build/Bough-0.X.Y.dmg

# 4. 同步产物到 gh-pages 并推送两个分支（见下"第 4 步"脚本）
```

---

## 一次性准备（已完成，换机时重做）

| 项 | 状态 / 恢复方式 |
|---|---|
| Developer ID Application 证书 | 登录钥匙串（`security find-identity -p codesigning` 可查） |
| 公证凭据 | 钥匙串 profile `Bough-notary`（`xcrun notarytool store-credentials Bough-notary` 重建；**App 专用密码在 appleid.apple.com 生成**，勿入聊天/仓库） |
| Sparkle EdDSA 私钥 | **登录钥匙串**。换机/重装前必须导出：`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x <导出文件>`；公钥已嵌入 Info.plist `SUPublicEDKey`。**私钥丢失 = 老用户永远收不到通过验证的更新** |
| gh-pages 分支 | 已在 GitHub 托管下载页（Pages 已开启，Source=gh-pages / root） |
| 推送通道 | SSH over 443（`~/.ssh/config`：github.com → ssh.github.com:443，密钥 `bough_mbp_ed25519`）。**当前网络对 GitHub HTTPS 有劫持（api.github.com 解析异常）——永远不要用 `GIT_SSL_NO_VERIFY` 或关闭任何证书校验** |

---

## 标准发版流程详解

### 第 0 步：代码就绪

- 全部改动已提交，工作树干净（`git status`）
- 全量测试绿：`xcodebuild test -project Bough.xcodeproj -scheme Bough -destination 'platform=macOS'`
- scheme 已关并行（project.yml `parallelizable: false`）——git 集成测试并行会偶发失败，勿改回

### 第 1 步：版本号

`Configs/Base.xcconfig`：

```
MARKETING_VERSION = 0.4.0      // 用户可见；破坏性/新功能升次版本，修 bug 升修订号
CURRENT_PROJECT_VERSION = 6    // build 号：每次发版 +1；Sparkle 以此判断新旧（apple 常规）
```

提交：`git commit -m "chore: bump version to 0.X.Y"`

> ⚠️ Sparkle 只会向**更高 sparkle:version（= build 号）**推送更新——build 号回退/复用会导致用户收不到更新。

### 第 2 步：打包

```bash
TEAM_ID=3LJQQ4T4DD ./Scripts/release.sh          # 全流程（含公证）
TEAM_ID=3LJQQ4T4DD NOTARIZE=0 ./Scripts/release.sh  # 本地试跑（跳过公证，产物不可分发）
```

内部 7 步：xcodegen 重新生成工程 → archive → Developer ID 导出 → zip 提交公证（`--wait`）→ staple → `spctl` 验证 → DMG（UDZO）。
产物：`build/Bough-0.X.Y.dmg`。**公证Accepted 后 app 才能分发**；`spctl -a -vv` 应显示 `accepted / Notarized Developer ID`。

### 第 3 步：appcast 更新（最容易出错的一步，逐项核对）

```bash
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update build/Bough-0.X.Y.dmg
# 输出：sparkle:edSignature="..." length="NNNN"
```

编辑 `Scripts/appcast-sample.xml`——**appcast 是多 item 文件**（新 item 在上，旧 item 保留以支撑老客户端更新路径）：

1. 复制现有最新 item 一份置于顶部，只改四处：
   - `<title>Version 0.X.Y</title>`
   - `<sparkle:version>N</sparkle:version>`（= build 号）
   - `<sparkle:shortVersionString>0.X.Y</sparkle:shortVersionString>`
   - `enclosure url` 的文件名 + 新签名/length
2. **enclosure url 域名必须是 `https://jade-ocean.github.io/Bough/`**——历史事故：曾把占位域名（wangyuyang.dev）带上线，更新静默失败
3. `sparkle:edSignature` / `length` 与**新 DMG 字节级对应**——重新打包（哪怕改一个字节）必须重新 `sign_update`，否则用户端验签拒绝
4. 改完校验 XML：`python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('Scripts/appcast-sample.xml')"`

### 第 4 步：同步 gh-pages 并推送

gh-pages 分支内容（下载页 + 全部历史版本 DMG + appcast）。当前用独立仓库 + fetch 搬运（不碰主工作区）：

```bash
# 产物入 gh-pages 工作目录
cp build/Bough-0.X.Y.dmg build/gh-pages/
cp Scripts/appcast-sample.xml build/gh-pages/appcast.xml
# 更新下载页版本号（index.html 中两处 0.3.1/0.4.0 字样 → 新版本）
#   build/gh-pages/index.html

# 提交并搬运到主仓库的 gh-pages ref
cd build/gh-pages && git add -A \
  && git -c user.name="wangyuyang" -c user.email="854266367@qq.com" \
       commit -m "release: Bough 0.X.Y" && cd - 
git fetch build/gh-pages gh-pages:refs/heads/gh-pages

# 推送两个分支
git push origin gh-pages
git push origin main        # appcast-sample 的改动也在 main
```

同时更新本地 `build/dist/`（托管暂存镜像：新 DMG + 旧 DMG 保留 + appcast）。

### 第 5 步：验证（发版必做）

```bash
# Pages 构建完成后（约 1-2 分钟，CDN 有延迟）
curl -s https://jade-ocean.github.io/Bough/appcast.xml | grep -E "shortVersionString|enclosure"
curl -sI https://jade-ocean.github.io/Bough/Bough-0.X.Y.dmg | head -1   # 期望 HTTP/2 200
```

核对三点：新 item 在最上、`sparkle:version` 递增、enclosure 域名 = `jade-ocean.github.io`。
本地重装验收：`ditto build/export/Bough.app /Applications/Bough.app` 后启动。

---

## 自动更新机制（为什么这样发就能被收到）

- 已装客户端（0.3.1+）内嵌 `SUFeedURL = https://jade-ocean.github.io/Bough/appcast.xml`，启动即检查（BUG-004 修复后启动触发生效）
- Sparkle 比较 `sparkle:version`（build 号）→ 有更新弹窗 → 用户确认 → 按 **enclosure url** 下载 → **EdDSA 验签**（公钥在客户端 Info.plist）→ 安装重启
- 因此三个一致性格外重要：**build 号递增、签名与 DMG 匹配、enclosure 可达且域名正确**

## 故障排查

| 症状 | 原因 / 处置 |
|---|---|
| 公证卡住/失败 | `xcrun notarytool log <id> --keychain-profile Bough-notary` 看详细报告；常见： hardened runtime 缺失、未签名框架 |
| `sign_update` not found | 路径见速查第 3 步（SPM 产物内），勿装全局旧版 |
| 用户收不到更新 | 检查 build 号是否递增 → appcast 是否已推 gh-pages → CDN 延迟（等 2 分钟再 curl）→ 客户端 Info.plist 的 `SUPublicEDKey` 是否与当前签名私钥配对 |
| 更新下载失败 | **查 enclosure 域名**（历史事故）；`curl -I` enclosure url 应 200 |
| push 失败提示认证 | 走 SSH over 443（见一次性准备）；`ssh -T git@github.com` 应回 "Hi jade-ocean!" |
| gh / api.github.com 证书错误 | 当前网络对 GitHub HTTPS 有劫持——SSH 443 不受影响；**切勿关证书校验** |

## 附：本仓库相关文件

- `Scripts/release.sh` — 打包流水线
- `Scripts/ExportOptions.plist` — Developer ID 导出配置
- `Scripts/appcast-sample.xml` — 线上 appcast 的事实源（改完同步 build/gh-pages）
- `Scripts/make_appicon.swift` / `make_appicon_layers.swift` — 图标（10 尺寸位图 / 三图层 SVG）
- `build/dist/` — 托管暂存镜像（与 gh-pages 内容一致）
