# Cell-lct Next

Cell-lct Next `v0.2.0` 是面向 Windows、Codex Desktop 与 Adobe Illustrator 2026 的稳定版科研矢量绘图插件。它将参考图重建为可编辑路径和真实 SVG 文本，并续画到用户已经打开的 Illustrator 文档中。

## 稳定版保证

- 固定源码版本：Git Tag `v0.2.0`。
- 固定 Python 依赖：`requirements.lock`。
- 固定运行契约：`runtime-lock.json`。
- 一键安装与诊断：`setup.ps1`、`doctor.ps1`。
- Windows 自动端到端测试，另提供 Illustrator 2026 人工触发真机测试。
- Release ZIP 配套独立 SHA256 文件。
- 不提供 Marketplace 安装入口；从固定 Tag 或 Release ZIP 安装。
- API Key 不随项目分发，只通过当前 Windows 账户的 DPAPI 加密保存。

## 环境要求

- Windows 10/11 x64
- Codex Desktop，且当前任务具备内置 Image 2 图片编辑能力
- Adobe Illustrator 2026（30.x）
- PowerShell 5.1 或更高版本
- Python 3.11–3.14

## 从固定 Tag 一键安装

```powershell
git clone --branch v0.2.0 --depth 1 https://github.com/yrui-cmd/cell-lct-next.git
Set-Location .\cell-lct-next
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

首次安装会安装锁定依赖、复制 Skill、在终端中安全提示录入 API Key，并运行诊断。API Key 不应写进命令、仓库、截图或聊天记录。

如果已经存在同名 Skill，并确认要替换：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Force
```

安装后重启 Codex，并新建任务。先由用户打开 Illustrator 2026 和目标文档，然后发送：

```text
使用 $cell-lct-next，根据我上传的内容或图片在当前 Illustrator 画板中作图，保留全部已有内容。
```

## 从 Release ZIP 安装

下载同一版本的两个文件：

- `cell-lct-next-v0.2.0.zip`
- `cell-lct-next-v0.2.0.zip.sha256`

验证后解压并运行 `setup.ps1`：

```powershell
$zip = '.\cell-lct-next-v0.2.0.zip'
$expected = ((Get-Content "$zip.sha256") -split '\s+')[0]
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'SHA256 校验失败，停止安装。' }
Expand-Archive $zip -DestinationPath .\cell-lct-next-v0.2.0
Set-Location .\cell-lct-next-v0.2.0\cell-lct-next-v0.2.0
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

## 诊断

```powershell
.\doctor.ps1
.\doctor.ps1 -VerifyApi -RequireIllustratorOpen
.\doctor.ps1 -Json
```

诊断只检查 Illustrator 注册和进程状态，不会启动、重启、聚焦、最大化或关闭 Illustrator。

## 工作方式

- 先记录参考图文字的内容、位置、尺寸、字体、字重、颜色、旋转、对齐和层级。
- Image 2 只清除文字，保留箭头、框、坐标轴、热图、图例、科研主体和原布局。
- 完整清理图进入矢量识别；返回后先在 Master SVG 中合并真实可编辑 `<text>`。
- SVG 只解析一次并建立几何缓存，全程复用一个 Illustrator 连接。
- 普通批次为 20–50 条路径，复杂路径可单独处理。
- 不删除、不隐藏、不替换已有画板内容；PNG 只在结束时导出。

## 测试与发行

```powershell
.\tests\test-package.ps1
.\tests\test-windows-e2e.ps1
.\build-release.ps1
```

Illustrator 真机测试会向当前打开的文档写入测试图，只能在一次性测试文档中显式运行：

```powershell
.\tests\test-illustrator-e2e.ps1 -ConfirmDisposableOpenDocument
```

生成的 ZIP 与 SHA256 位于 `dist`。CI 使用 Windows runner 执行离线绘制链路测试；Illustrator 真机链路仅在带 Illustrator 2026 的自托管 Windows runner 上人工触发。

## 可复现性边界

仓库可以固定 Skill、脚本、依赖、测试和发行文件，但无法把 Codex 内置 Image 2 或 Adobe Illustrator 本体打包进去。另一台电脑要获得一致流程，必须满足 `runtime-lock.json` 中的环境契约，并自行配置 DPAPI API Key。

完整插件源码位于 `plugins/cell-lct-next`，安装器只把其中的 `cell-lct-next` Skill 部署到用户的 Codex Skills 目录。原版 Cell-lct 与 Cell-lct Next 可以并存。
