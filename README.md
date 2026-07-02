# clipcap

macOS 菜单栏图片标注工具。clipcap 不直接捕获屏幕，不录制屏幕，不监听全局键盘事件，也不需要 Screen Recording 和 Accessibility 权限

## 推荐流程

1. 按 `Control + Shift + Command + 4` 使用 macOS 系统截图，并把区域截图复制到剪贴板
2. 在菜单栏点击 clipcap，选择“编辑剪贴板图片”
3. 标注、OCR、翻译、上传、保存，或复制结果

也可以把图片文件拖到应用、使用“打开图片”、从 Finder 里选择“Open With clipcap”，或把图片复制到剪贴板后交给 clipcap 编辑

## 功能

- 编辑剪贴板图片和本地图片文件
- 箭头、矩形、圆形、线条、画笔、荧光笔、马赛克、文字、编号、贴图、二维码识别
- OCR、截图翻译、词典模式和翻译服务配置
- 图片上传到自定义图床，并复制链接或 Markdown
- 保存到本地文件夹，保留历史记录，支持重新复制历史图片
- 菜单栏常驻，无 Dock 图标

## 隐私边界

clipcap 的输入来自系统剪贴板、打开面板、文件拖拽、Open With 和用户明确选择的图片文件。应用不会请求或复用旧应用的 TCC 权限，不会使用全局热键触发屏幕捕获，也不会通过 Finder Automation 读取选中文件

## 安装

Homebrew 安装

```bash
brew install --cask realskyrin/tap/clipcap
```

更新

```bash
brew update
brew upgrade --cask realskyrin/tap/clipcap
```

卸载

```bash
brew uninstall --cask realskyrin/tap/clipcap
```

也可以从 [GitHub Releases](https://github.com/realskyrin/clipcap/releases/latest) 下载 DMG，打开后把 `clipcap.app` 拖到 Applications

```bash
open ~/Downloads/clipcap-<version>-macos.dmg
```

如果手动下载安装后 macOS 提示无法打开，可以移除下载隔离属性后再启动

```bash
xattr -dr com.apple.quarantine /Applications/clipcap.app
open /Applications/clipcap.app
```

如果应用已经在运行，重启应用

```bash
pkill -x clipcap || true
open /Applications/clipcap.app
```

手动构建会输出到 `build/clipcap.app`

```bash
bash scripts/compile-check.sh
bash scripts/rebuild-and-open.sh
```

## 项目结构

- `clipcap/App/`：应用入口和 bundle 元数据
- `clipcap/Capture/`：剪贴板、历史记录、钉图和图片编辑入口
- `clipcap/Editor/`：标注模型、编辑画布、工具栏、保存、上传、OCR 和翻译入口
- `clipcap/Settings/`：设置窗口、工具栏、上传和翻译配置
- `clipcap/Upload/`：图床实现
- `clipcap/Utilities/`：默认值、本地化、更新、日志和保存路径
- `scripts/`：构建、打包、安装和签名脚本

## 发布

Bundle ID：`cn.skyrin.clipcap`

App bundle：`clipcap.app`

Release artifact：`clipcap-<version>-macos.dmg`

Homebrew cask：`clipcap`
