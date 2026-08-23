# 描绘心声

**Science Speaks in Vectors**

面向 Codex Desktop 与 Adobe Illustrator 2026 的科研矢量绘图插件。它可以根据文字或参考图片生成真 SVG，并把可编辑原生路径追加到用户已经打开的 Illustrator 文档中，同时保留已有内容。

> 本项目为独立第三方工具，与 Adobe 无隶属、赞助或官方认可关系。

## 仓库现在包含什么

- `miaohui-xinsheng`：面向用户的统一入口 Skill。
- `lct-all`：完整绘图编排与当前画板续画流程。
- `lct-slt`：科研图生成、参考图重建、SVG 验证及小描连接。
- `lct-ht`：Illustrator 2026 原生可编辑路径写入运行时。
- `install.ps1`：把全部 Skill 一次安装到本机 Codex。
- Codex 插件清单与仓库 Marketplace 清单。

API Key 不在仓库中，也不会写入生成文件；首次配置时使用 Windows DPAPI 加密后保存在当前 Windows 用户目录。

## 给另一台电脑上的 Codex：一句话安装

把下面整句发给 Codex：

```text
请克隆 https://github.com/yrui-cmd/miaohui-xinsheng，检查后运行仓库根目录 install.ps1 安装全部 Skill；随后以隐藏输入方式运行 lct-slt/scripts/set-xiaomiao-key.ps1 配置我接下来提供的 API Key，验证连接成功后提醒我重启 Codex并新建任务，然后使用 $miaohui-xinsheng 根据我上传的文字或图片在当前 Illustrator 画板开始作图。
```

不要把真实 API Key 写入上述公开文本、Git 提交、Issue 或截图；在 Codex 请求输入时单独提供。

## 手动安装

```powershell
git clone https://github.com/yrui-cmd/miaohui-xinsheng.git
Set-Location .\miaohui-xinsheng
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

已有同名 Skill 且确认需要替换时：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

也可把仓库作为 Codex Marketplace 安装：

```powershell
codex plugin marketplace add .
codex plugin add miaohui-xinsheng@miaohui-xinsheng-tools
```

安装或更新后，请重新启动 Codex 并新建任务。

## 首次配置

1. 打开交互终端，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\plugins\miaohui-xinsheng\skills\lct-slt\scripts\set-xiaomiao-key.ps1
```

2. 在隐藏输入提示中粘贴 API Key 并按 Enter。
3. 验证连接：

```powershell
powershell -ExecutionPolicy Bypass -File .\plugins\miaohui-xinsheng\skills\lct-slt\scripts\xiaomiao.ps1 verify
```

## 使用前准备

- Windows 10/11。
- Codex Desktop。
- Python 3，可通过 `py -3` 调用。
- Adobe Illustrator 2026。
- 用户已自行打开目标 AI 文档。
- 有效的小描 API Key 与可用额度。

插件不会启动、重启、关闭、置顶或调整 Illustrator 窗口，只负责向当前已经打开的文档追加绘图。

## 开始作图

```text
使用 $miaohui-xinsheng，在当前画板右上角画一个小兔子。保留全部已有内容。
```

参考图片重绘：

```text
使用 $miaohui-xinsheng，参考我上传的图片，在当前画板中上方重绘。保留全部已有内容，不要覆盖文字。
```

暂停与继续：

```text
暂停。
```

```text
继续完成刚才的绘图，保留全部已经完成的内容。
```

## 统一科研绘图提示词

```text
使用 $miaohui-xinsheng。

你是一名经验丰富的科研绘图设计师。请根据我提供的研究内容，绘制符合顶级期刊标准的 BioRender 风格科研配图，并严格遵守以下规范：

1. 采用清晰的科研矢量插画风格，避免照片感和写实感。
2. 使用纯白色背景和扁平化 2D 设计，禁止任何 3D 渲染。
3. 禁止使用光影渐变、镜面反射、复杂纹理、电影级光效、立体阴影及其他写实效果。
4. 整体保持简约、整洁，所有线条干净流畅，颜色使用纯色色块平涂。
5. 构图、配色、比例、留白和信息层级应符合行业顶级期刊的科研绘图标准。
6. 全图中的同类事物必须保持绝对一致，包括颜色、形状、大小、比例、线宽、结构和内部细节。
7. 所有重复小元素必须分别绘制为彼此独立的单个图形，不得相互连接、融合、共用外轮廓或连成一个整体。

绘图内容：【填写研究内容或对象】
绘制位置：【填写画板位置】
绘制尺寸：【填写尺寸或画板占比】
避让区域：【填写不能覆盖的文字或图形】
其他要求：【填写配色、标签或结构要求】

保留当前画板中的全部已有内容，不得删除、隐藏、替换或覆盖。
```

## 安全与故障排查

- 不要把患者隐私、未公开数据、密码或 API Key 上传到公开仓库与 Issue。
- 开始前先保存重要 AI 文档备份。
- 如果提示 Illustrator 不可用，请自行打开 Illustrator 2026 和目标文档后重试。
- 如果提示密钥未配置，请重新运行 `set-xiaomiao-key.ps1`。
- 如果提示额度不足，请停止重复请求并检查小描账户额度。
- 提交 Issue 时请提供系统、Codex 与 Illustrator 版本、去敏后的提示词和截图。

## 商标说明

Adobe 和 Adobe Illustrator 是 Adobe 在美国及其他国家或地区的注册商标或商标。本项目仅以兼容性说明方式引用相关名称。
