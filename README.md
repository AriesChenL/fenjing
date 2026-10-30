# 分境 · FenJing

**Author: lynn · caused by codex**

[下载 macOS Apple Silicon 预览版](https://github.com/AriesChenL/fenjing/releases) · [开源许可](LICENSE)

macOS 13+ / Apple Silicon 的独立指纹浏览器应用。自有图形界面、自有图标与启动器，安装包内置 Fingerprint Chromium，无需安装 CCBaga、Rust、Node.js 或其他浏览器。

## 使用

1. 打开 `FenJing.app`，点击「新建环境」。
2. 填写名称、备注、语言和时区；指纹种子会自动生成，也可以手动指定。
3. 起始页默认 Google；留空也打开 Google。
4. 需要代理时打开「为此环境启用独立代理」。默认 HTTP，填写一组主机和端口即可；HTTPS、SOCKS5 共用相同表单。
5. 点击卡片上的「启动浏览器」。每个环境可同时运行，首次使用需要分别登录。
6. Dashboard 的「正常退出」、 「正常退出所选」或「正常退出全部」会发送原生退出请求，确认退出后才更新状态，并保留浏览器资料。下载或关闭确认未处理时会提示，不假报已退出。

界面使用原生 `NSVisualEffectView` 磨砂背景、半透明侧栏、圆角工作区与环境卡片。每个环境分别保存 Cookie、历史、密码库和扩展资料，使用稳定指纹种子。复制环境只复制配置，并生成新的指纹和资料目录。

退出管理器不会退出浏览器；重新打开管理器会识别既有进程。「移除环境」只移除列表条目，保留资料文件。

## 数据和代理

资料目录：`~/Library/Application Support/FenJing/`，配置文件为 `environments.json`，环境资料位于 `profiles/<UUID>/`。目录/配置使用 0700/0600 权限。损坏配置、重复指纹种子、符号链接路径和未知进程状态会阻止相应写操作。

每个环境只保存一组代理配置。支持 HTTP、HTTPS、SOCKS5 的无凭据地址；当前不保存或自动填写代理用户名/密码，认证代理可通过本机代理客户端转接。关闭独立代理时沿用系统网络 / TUN，不自动获得不同 IP。

持久 Cookie 与本地存储会保留；会话 Cookie 依照 Chromium 自身规则处理。环境分开保存不等于操作系统沙箱隔离，也不保证匿名或任何网站的账号状态。

## 构建

仅需 Xcode Command Line Tools、Python 3 和 macOS 系统工具。引擎版本固定为 Fingerprint Chromium `148.0.7778.215`。

从仓库根目录准备经过摘要校验的上游引擎，再构建：

```sh
python3 scripts/fetch-engine.py
bash scripts/build.sh
```

也可通过 `FENJING_ENGINE_SOURCE=/absolute/path/Browser.app` 指定兼容的本地构建输入。该路径仅供打包阶段使用，不进入运行时配置。产物是 `build/FenJing.app`。

生成安装包：

```sh
bash scripts/package-dmg.sh
```

安装包和 SHA-256 校验文件位于 `dist/`。

构建会复制完整引擎并保留内部 Framework 链接，移除旧宿主启动器，设置分境名称/图标/独立应用标识，编译自己的启动器，按叶子到容器顺序进行本地临时签名，并保留必要许可证。运行时只从自身应用包加载浏览器。

目前提供本地临时签名构建。公开分发给其他 Mac 之前需要 Developer ID 签名、公证和相应的发布验证；当前没有提供 Intel 或 Windows 版本。

## 验证

```sh
bash scripts/test-core.sh
node Tests/browser-integration.mjs
node Tests/browser-integration.mjs --proxies
python3 scripts/verify-bundle.py /absolute/path/FenJing.app
```

真实浏览器测试使用临时资料目录和本机页面，检查同时运行、不同稳定 Canvas 指纹、语言/时区、定位权限、同源 Cookie/localStorage 隔离、持久资料重启恢复、单独正常退出和独立 HTTP 代理。测试结束会正常退出并删除测试目录。正常产品启动不开放调试端口。

可设置 `FENJING_TEST_ENGINE` 指向已搬移的应用包内引擎，验证交付包的独立运行。GUI 已实际检查新建、编辑、复制、搜索、HTTP 表单校验、批量启动、Google 默认页及管理器重开识别。

## 许可

部分进程识别和启动参数代码改编自 MIT 授权的 CCBaga，原作者版权声明予以保留。浏览器基于开源 Fingerprint Chromium。具体来源和条款随应用保存在 `Contents/Resources/ThirdPartyNotices.txt`，也可从「关于分境 → 开源许可」打开。应用界面、图标、启动器和浏览器应用名称不使用 CCBaga 品牌素材。

## GitHub Actions 自动打包

工作流改编自上游公开仓库的 macOS 发布流程，使用固定提交版本的 GitHub Actions。PR 会构建并生成测试产物；也可以在 Actions 中手动运行。推送与应用版本匹配的标签（例如 `v0.1.0`）后，会自动下载并校验固定版本引擎、构建、运行核心回归、验证应用包、生成 DMG 和 SHA-256，并发布预览版 Release。

工作流不需要额外设置 Apple 凭据。当前生成临时签名的预览包，Developer ID 签名和 Apple 公证尚未配置。
