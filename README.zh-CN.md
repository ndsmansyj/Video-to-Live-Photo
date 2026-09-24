<p align="center">
  <img src="Assets/README/hero.svg" alt="Video to Live Turbo" width="100%">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

# Video to Live Turbo

一个原生 macOS 小工具：**把普通视频快速变成 iPhone Live Photo。**

**Video → Live Photo → iPhone**

全程本地处理，不需要 iCloud、不写入 Mac 照片图库、不依赖服务器，也不会移动、覆盖、修改或删除原视频。

## 功能

- 默认生成约 3 秒 Live Photo，可自定义时长直到完整原视频
- 初始封面位于选区开头；封面可在选区内自由移动，越界时选区自动跟随
- 手动生成前可选择保留声音或静音
- 支持 MOV / MP4 / M4V 与批量导入、批量生成、批量 AirDrop
- 可选自动转换指定文件夹中的新视频，适配任意软件导出工作流
- 历史结果按日期整理，可重新 AirDrop、重新调整并在 Finder 中定位
- 转换核心提供 CLI，可被 Agent 与脚本直接调用

> 朋友圈仅支持 3 秒 Live；App 默认时长为 3 秒。

<p align="center">
  <img src="Assets/README/workflow.svg" alt="Video to Live Turbo 工作流" width="100%">
</p>

## 手动工作流

1. 打开 **Video to Live Turbo**。
2. 导入一个或多个视频；素材先进入 **待生成**，此时不会输出文件。
3. 点击画面调整片段、封面和时长；按需选择是否保留声音。
4. 点击 **生成 Live Photo**，App 才会创建配对的 HEIC + MOV。
5. 在 **本次生成** 中选择结果，AirDrop 到 iPhone。

## 自动转换文件夹

在 **设置 → 自动化** 中开启 **自动转换文件夹中的新视频** 并指定文件夹。

App 打开时会扫描该文件夹，运行期间持续检测新视频并自动转换。它不绑定任何剪辑软件，可用于相机拷贝目录、下载目录，或 DaVinci Resolve、Final Cut Pro、Premiere Pro 等软件的导出目录。

## Agent / CLI

转换核心可以不经过 App UI 直接调用，适合 Agent、Shell 脚本和本地自动化：

```bash
spp-live-export [--cover 秒] [--start 秒] [--duration 秒] [--mute] <video> [output_dir]
```

CLI 控制的是转换核心；首页、待生成列表、历史等 App UI 状态目前没有单独的 HTTP API。

## 安装

从 GitHub **Releases** 下载：

**Video to Live Turbo 1.0.0.dmg**

当前 1.0.0 使用 ad-hoc 签名，尚未 Apple Developer ID 公证。macOS 首次打开时如提示无法验证开发者，可进入：

**系统设置 → 隐私与安全性 → 仍要打开**

要求：

- Apple Silicon Mac
- macOS 13 或更新版本

从源码构建：

```bash
./scripts/build.sh
./scripts/build.sh --dmg
```

构建产物位于 `dist/`。

## 原始素材安全

Video to Live Turbo 按非破坏性流程处理素材。程序可以读取原视频，并创建新的 HEIC / MOV、处理标记及 AirDrop 临时缓存，但不会：

- 删除原视频
- 移动原视频
- 覆盖原视频
- 修改原视频内容

自动清理只针对 App 自己生成的失败半成品和 AirDrop 临时缓存。

## 兼容性

AirDrop 保持 Live Photo 依赖 macOS 对 `.pvt` / `com.apple.private.live-photo-bundle` 的系统识别。

当前流程已经在真实 Mac + iPhone 上验证：AirDrop 接收后可作为 Live Photo 正常播放。该 Bundle 类型属于 Apple 私有实现，未来系统大版本更新后仍可能发生变化。

`ffprobe` 不是转换依赖；如系统中存在 `/usr/local/bin/ffprobe` 或 `/opt/homebrew/bin/ffprobe`，App 会额外显示编码、分辨率和帧率等技术信息。

## License

MIT
