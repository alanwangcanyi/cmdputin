# CMDPutin

在 macOS 上选中目标窗口，将一条命令作为键盘输入发送过去。发送后请在目标窗口核对并手动按回车。命令不会保存。发送英文命令时，目标 console 请使用美式英语（US）键盘布局。

## 安装和运行

打开 `dist/CMDPutin-macOS.dmg`，将 CMDPutin 拖入“应用程序”。当前镜像适用于 Apple 芯片和 macOS 13 或更高版本。更新时先退出旧版，再替换应用。

```sh
open "/Applications/CMDPutin.app"
```

在命令框输入或粘贴单行命令。点“去授权”打开系统设置，在“隐私与安全性 → 辅助功能”启用 CMDPutin。列表里找不到时点 `+`，按 `⌘⇧G`，输入 `/Applications/CMDPutin.app`。授权生效后，工具会自动列出窗口。选中目标窗口再点“输入”。如果系统仍显示旧名称，请用 `+` 添加上面的新版路径。点“置顶”可切换窗口层级。

## 构建

安装 macOS 命令行开发工具后，在项目根目录运行 `bash tools/build_dmg.sh`。脚本会从 `macOS/main.swift` 构建原生 AppKit 应用，使用 `assets/` 中的黑色 SVG 生成图标，并生成适合当前 Mac 架构的 DMG。
