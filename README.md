# `Cell-lct` Skill

[English](README_EN.md)

**描绘心声 · Science Speaks in Vectors**

`Cell-lct` 是面向 Codex Desktop 与 Adobe Illustrator 2026 的科研矢量绘图 Skill。它可以根据研究描述或参考图片，在用户当前打开的 Illustrator 文档中生成、重绘并续画可编辑科研图，同时保留画板中的已有内容。

> 本项目为独立第三方工具，与 Adobe 无隶属、赞助或官方认可关系。

## 适合用它做什么

- 绘制细胞、器官、动物、蛋白分子、实验装置等科研素材。
- 重绘机制图、流程图、Graphical Abstract 和综述示意图。
- 参考 PNG、JPG、JPEG 或 WebP 图片生成新的可编辑矢量版本。
- 在当前 Illustrator 画板指定位置继续添加内容，不清除已有对象。
- 保留普通文字为 Illustrator 可编辑文字，而不是把文字转成轮廓。

## 工作方式

`Cell-lct` 以当前 Illustrator 文档为唯一画布：

1. 理解用户提供的研究内容、参考图片、绘制位置和避让区域。
2. 生成并检查新的真矢量图形。
3. 按视觉顺序把可编辑路径和文字追加到当前画板。
4. 中途暂停时保留已经完成的内容，继续时从未完成位置接着绘制。
5. 完成后保留 AI 源文件中的原生可编辑对象。

它不会替用户启动、重启、关闭、置顶或调整 Illustrator 窗口；使用前请自行打开 Illustrator 2026 和目标文档。

## 典型请求

- “使用 `$cell-lct`，在当前画板右上角画一个小兔子，保留全部已有内容。”
- “使用 `$cell-lct`，参考我上传的图片，在画板中上方重绘，不要覆盖已有文字。”
- “使用 `$cell-lct`，根据这段研究内容绘制扁平化 2D 机制图，文字保持可编辑。”
- “继续完成刚才暂停的绘图，不要删除已经画好的内容。”

## 你需要提供

- 研究内容、目标对象或一张参考图片。
- 希望绘制的位置、尺寸或画板占比。
- 不能覆盖的文字、图形或其他避让区域。
- 必要的标签、配色、箭头关系和结构要求。

## 产出

- 当前 Illustrator 文档中的原生可编辑矢量路径。
- 可继续修改的 Illustrator 文字对象。
- 与当前画板已有内容共存的新增图形。
- 需要时生成 SVG 等中间文件；文件名按 `shibielujing1`、`shibielujing2`、`shibielujing3`……递增。

## 快速安装

### 交给另一台电脑上的 Codex

把下面一句话发送给对方的 Codex：

```text
请从 https://github.com/yrui-cmd/cell-lct 安装 plugins/cell-lct/skills/cell-lct 目录中的 Cell-lct Skill，完成依赖检查并以隐藏输入方式配置 API Key；安装完成后提醒我重启 Codex、新建任务并使用 $cell-lct 开始作图。
```

API Key 请单独私下提供，不要写入公开提示词、Git 提交、Issue、聊天截图或生成文件。

### 手动安装

在 Windows PowerShell 中运行：

```powershell
git clone https://github.com/yrui-cmd/cell-lct.git
Set-Location .\cell-lct
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

确认需要替换已有同名 Skill 时：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

安装或更新后，请重新启动 Codex 并新建任务。

## 首次配置

### 环境要求

- Windows 10/11。
- Codex Desktop。
- Adobe Illustrator 2026，并已打开目标文档。
- Python 3，可通过 `py -3` 调用。
- Python 包 `fontTools`。
- Windows 自带的 `curl.exe`。
- 有效的转换服务 API Key 与可用额度。

缺少 `fontTools` 时运行：

```powershell
py -3 -m pip install --user fonttools
```

使用隐藏输入配置 API Key，并验证连接：

```powershell
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\set-xiaomiao-key.ps1
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\xiaomiao.ps1 verify
```

API Key 不包含在仓库中；配置脚本会将其加密保存到当前 Windows 用户环境。

## 开始作图

### 简单对象

```text
使用 $cell-lct，在当前画板左上角画一个扁平化 2D 小鼠，保留全部已有内容。
```

### 参考图片重绘

上传参考图片后发送：

```text
使用 $cell-lct，参考我上传的图片，在当前 Illustrator 画板中重绘。保留全部已有内容，不要覆盖文字。
```

### 科研机制图

```text
使用 $cell-lct。

你是一名经验丰富的科研绘图设计师。请根据我提供的研究内容，绘制符合顶级期刊标准的 BioRender 风格科研配图：采用清晰的矢量插画、纯白背景和扁平化 2D 设计；禁止照片感、3D 渲染、复杂纹理、镜面反射和写实阴影；保持线条干净、色块平涂、层级清晰。同类事物的颜色、形状、大小、比例、线宽、结构和细节必须一致；所有重复小元素必须分别保持为独立可编辑对象。文字必须保留为 Illustrator 可编辑文字对象。

绘图内容：【填写研究内容或对象】
绘制位置：【填写画板位置】
绘制尺寸：【填写尺寸或画板占比】
避让区域：【填写不能覆盖的文字或图形】
其他要求：【填写配色、标签或结构要求】

保留当前画板中的全部已有内容，不得删除、隐藏、替换或覆盖。
```

### 暂停与继续

```text
暂停。
```

```text
继续完成刚才的绘图，保留全部已经完成的内容。
```

## 绘图标准

- 采用白色背景、平面化 2D 矢量风格和清晰视觉层级。
- 避免照片感、3D 渲染、复杂纹理、镜面效果和写实光影。
- 同类对象保持颜色、形状、比例、线宽、结构和细节一致。
- 重复小元素分别绘制为独立可编辑对象。
- 普通标签保留为可编辑文字，不默认转曲。
- 不删除、隐藏、替换或覆盖当前画板中的已有内容。

## 项目结构

项目核心是一个统一 Skill：

```text
plugins/cell-lct/skills/cell-lct/
├── SKILL.md
├── agents/openai.yaml
├── references/
└── scripts/
```

仓库同时保留 Codex 插件兼容包装，但普通用户只需安装 `cell-lct` Skill，不需要本地 Marketplace 链接，也不需要分别安装旧版 LCT Skill。

## 边界

- AI 生成的科研示意图需要研究者核对科学含义、标签和因果关系。
- 本工具不会把生成内容当作真实实验结果或定量数据证据。
- 不会凭空补充实验数据、统计结果、样本量或未提供的机制结论。
- 不要提交患者隐私、未公开敏感数据、密码或 API Key 到公开仓库与 Issue。
- 处理重要文件前，建议先保存 Illustrator 文档备份。

## 常见问题

### Codex 找不到 `$cell-lct`

确认 Skill 已安装到当前 Codex 的 Skills 目录，然后重新启动 Codex 并新建任务。

### 提示 Illustrator 不可用

自行打开 Adobe Illustrator 2026 和目标 AI 文档，再让 Codex 继续绘图。

### 提示 API Key 未配置或验证失败

重新运行 `set-xiaomiao-key.ps1`，再运行 `xiaomiao.ps1 verify`。

### 图片没有进入矢量转换流程

在请求中明确写出“使用 `$cell-lct`”，并确认 API Key、网络连接和账户额度均可用。

## 商标说明

Adobe 和 Adobe Illustrator 是 Adobe 在美国及其他国家或地区的注册商标或商标。本项目仅以兼容性说明方式引用相关名称。
