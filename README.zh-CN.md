<p align="center">
  <img src="Assets/README/hero.svg" alt="Video to Live Photo" width="100%">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

# Video to Live Photo

一个原生 macOS 小工具，用来把普通视频转换成 Apple 实况照片（Live Photo），并通过 AirDrop 直接发送到 iPhone。

**全程本地处理。** 不需要 iCloud，不写入 Mac 照片图库，不依赖服务器。

## 它解决什么问题？

普通情况下，即使 HEIC 图片和 MOV 视频拥有匹配的 Live Photo 元数据，直接把这两个文件一起 AirDrop 到 iPhone，收到的通常还是：

- 一张普通图片
- 一个独立 MOV 视频

而不是一张真正的“实况照片”。

Video to Live Photo 会：

1. 从视频中生成 Live Photo 所需的 HEIC + MOV 配对文件。
2. 给两者写入匹配的 Apple Live Photo 元数据。
3. 在 Mac 端封装成系统可识别的 Live Photo Bundle。
4. 通过 AirDrop 发送到 iPhone。
5. iPhone 最终收到的是一张真正的 Live Photo。

<p align="center">
  <img src="Assets/README/workflow.svg" alt="Video to Live Photo 工作流" width="100%">
</p>

## 主要功能

- 自动监听 DaVinci Resolve 导出目录
- 支持手动批量导入视频
- 支持 MOV / MP4 / M4V
- 尽可能使用视频流直通，不进行无意义的二次压制
- 以竖屏素材为主的缩略图浏览界面
- 按日期自动分组
- 支持“选择本日”
- 支持全选 / 取消全选
- 支持 Shift 连续选择
- 支持批量 AirDrop
- 历史记录可重新 AirDrop
- 可在 Finder 中定位生成文件
- 可自定义监听目录和输出目录
- 支持登录 Mac 后自动启动
- 支持紧凑 / 标准 / 大缩略图
- 可选显示分辨率、编码、帧率等技术信息
- 不依赖 Mac Photos 照片图库
- 不移动、不覆盖、不修改、不删除原始视频素材

## 使用方法

1. 打开 App。
2. 在“设置”中确认监听目录。
3. 在 DaVinci Resolve 中把视频导出到该目录。
4. 或点击“导入视频”手动选择一个或多个视频。
5. 等待 Live Photo 自动生成。
6. 单选、整日选择、Shift 连选或全选需要发送的内容。
7. 点击 **AirDrop**。
8. 选择你的 iPhone。
9. iPhone 相册中会收到真正的实况照片。

> 当前 v0.4.0 的 App 内部显示名称仍为 **SPP Live Export**。仓库公开名称已经调整为 **Video to Live Photo**，后续版本会逐步统一公开品牌名称，同时保留内部 Bundle ID 和数据目录以避免破坏已有设置。

## 安装

### 下载 DMG

到 GitHub 的 **Releases** 页面下载最新 DMG。

当前公开 DMG 使用本地 ad-hoc 签名，没有 Apple Developer ID 公证，因此 macOS 可能提示无法验证开发者。

如果遇到提示，可以进入：

**系统设置 → 隐私与安全性 → 仍要打开**

也可以直接从源码构建。

### 从源码构建

要求：

- Apple Silicon Mac
- macOS 13 或更新版本
- Apple Command Line Tools / Swift

构建 App：

```bash
./scripts/build.sh
```

构建 App + DMG：

```bash
./scripts/build.sh --dmg
```

生成文件位于 `dist/`。

## DaVinci Resolve 工作流

推荐把 Resolve 的输出目录设置成 App 的监听目录。

之后基本操作就是：

```text
DaVinci Resolve
    ↓
自动监听
    ↓
生成 Live Photo
    ↓
日期分组 / 批量挑选
    ↓
AirDrop
    ↓
iPhone 实况照片
```

不需要先导入 Mac Photos，也不需要再在手机上二次转换。

## 原始素材安全

这个项目按照“原片只读”的思路设计。

程序可以：

- 读取原始视频
- 创建新的 HEIC / MOV 输出
- 创建处理标记
- 创建自己的 AirDrop 临时缓存

程序只会自动清理：

- 自己产生且转换失败的半成品
- 自己的 AirDrop 临时缓存

程序不会：

- 删除原始视频
- 移动原始视频
- 覆盖原始视频
- 修改原始视频内容

## 关于 ffprobe

`ffprobe` **不是转换所必需的依赖**。

如果系统中存在：

- `/usr/local/bin/ffprobe`
- `/opt/homebrew/bin/ffprobe`

App 会额外显示编码、分辨率、帧率等技术信息。

没有 ffprobe 也不影响 Live Photo 转换和 AirDrop。

## 兼容性说明

目前 AirDrop 后能够保持 Live Photo，依赖 macOS 对：

`com.apple.private.live-photo-bundle`

也就是 `.pvt` Live Photo Bundle 的系统识别。

这条链路已经在真实 Mac + iPhone 上验证可用，但它属于 Apple 的私有 Bundle 类型，未来 macOS / iOS 大版本更新后存在变化的可能。

## 开源协议

MIT
