# Cell-lct

**Science Speaks in Vectors**

Cell-lct 是面向 Codex Desktop 与 Adobe Illustrator 2026 的科研矢量绘图插件。它根据文字或参考图片生成真 SVG，并把可编辑原生路径和可编辑文字追加到用户已经打开的 Illustrator 文档中，同时保留已有内容。

> 本项目为独立第三方工具，与 Adobe 无隶属、赞助或官方认可关系。

## 包含内容

公开包只安装一个统一 Skill：`cell-lct`。图片转换、结构验证、缓存播放、Illustrator 路径写入和可编辑文字均由该 Skill 内部完成，不需要再单独安装其他 Skill。

API Key 不在仓库中，也不会写入生成文件；首次配置时使用 Windows DPAPI 加密后保存在当前 Windows 用户目录。

## 给另一台电脑上的 Codex：一句话安装

```text
请克隆 https://github.com/yrui-cmd/cell-lct，检查后运行仓库根目录 install.ps1 安装 Cell-lct；随后以隐藏输入方式运行 scripts/set-xiaomiao-key.ps1 配置我接下来提供的 API Key，验证连接成功后提醒我重启 Codex 并新建任务，然后使用 $cell-lct 根据我上传的文字或图片在当前 Illustrator 画板开始作图。
```

不要把真实 API Key 写进公开提示词、Git 提交、Issue 或截图；在 Codex 请求隐藏输入时单独提供。

## 手动安装

```powershell
git clone https://github.com/yrui-cmd/cell-lct.git
Set-Location .\cell-lct
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

已有同名 Skill 且确认需要替换时：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force
```

也可把仓库作为 Codex Marketplace 安装：

```powershell
codex plugin marketplace add .
codex plugin add cell-lct@cell-lct-tools
```

安装或更新后，请重新启动 Codex 并新建任务。

## 首次配置

```powershell
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\set-xiaomiao-key.ps1
powershell -ExecutionPolicy Bypass -File .\plugins\cell-lct\skills\cell-lct\scripts\xiaomiao.ps1 verify
```

## 使用前准备

- Windows 10/11。
- Codex Desktop。
- Python 3，可通过 `py -3` 调用。
- Adobe Illustrator 2026。
- 用户已自行打开目标 AI 文档。
- 有效的 API Key 与可用额度。

Cell-lct 不会启动、重启、关闭、置顶或调整 Illustrator 窗口，只负责向当前已经打开的文档追加绘图。

## 开始作图

```text
使用 $cell-lct，在当前画板右上角画一个小兔子。保留全部已有内容。
```

参考图片重绘：

```text
使用 $cell-lct，参考我上传的图片，在当前画板中上方重绘。保留全部已有内容，不要覆盖文字。
```

上传 PNG、JPG、JPEG 或 WebP 后，Cell-lct 会强制调用已配置的转换服务生成新的真矢量 SVG；密钥未配置或验证失败时会停止并要求配置，不会静默改用本地描摹、旧 SVG 或位图包装。已经验证为真矢量的 SVG 不重复转换。

暂停与继续：

```text
暂停。
```

```text
继续完成刚才的绘图，保留全部已经完成的内容。
```

## 科研绘图提示词

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

## 安全与故障排查

- 不要把患者隐私、未公开数据、密码或 API Key 上传到公开仓库与 Issue。
- 开始前先保存重要 AI 文档备份。
- 如果提示 Illustrator 不可用，请自行打开 Illustrator 2026 和目标文档后重试。
- 如果提示密钥未配置，请重新运行 `set-xiaomiao-key.ps1`。
- 如果提示额度不足，请停止重复请求并检查账户额度。

## 商标说明

Adobe 和 Adobe Illustrator 是 Adobe 在美国及其他国家或地区的注册商标或商标。本项目仅以兼容性说明方式引用相关名称。
