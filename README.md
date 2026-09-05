# cell_gd

原图直接进入路径识别，使用者选择 **PPT 或 Adobe Illustrator**，随后沿用原 cell-ppt / cell-lct 的绘图与后处理。

## 流程

1. 提供原始 PNG、JPEG 或 WebP。
2. 选择 PPT 或 Adobe Illustrator。
3. 原图完整上传路径识别；不提取文字、不生成文字清单、不用 Image 2 去字、不回填文字。
4. 识别得到的 SVG 进入所选绘图分支。图片里的字随图识别，可能成为可编辑路径，不承诺文本框。
5. PPT 保存可编辑 PPTX；Illustrator 保存 AI，并在完成后导出 PNG。

PPT 保留原逐路径去重、绘制顺序、8 ms 间隔、已有对象保护及 macOS OOXML 后端。Illustrator 保留原缓存、20–50 对象批次、单连接续画、断点恢复、定时保存与最终导出。

## 安装

Windows：运行 `setup.ps1`；macOS：运行 `bash setup.sh`。安装后的 skill 名和目录均为 `cell_gd`。两个原仓库提供同一个完整 skill，任选一个安装即可；不要同时安装同名副本。旧版不会被自动删除。

Windows 支持 PPT 和 Illustrator；Illustrator 沿用已有 Windows / Illustrator 2026 运行要求，需先打开目标文档。macOS 沿用 PPT 的可编辑 OOXML 后端。

API 密钥配置和额度规则沿用原适配器。原有安全凭据命名空间保持兼容。

## 调用

告诉 Codex：`用 cell_gd 处理这张原图，用 PPT 绘制。` 或 `用 cell_gd 处理这张原图，用 Adobe Illustrator 绘制。`

Windows 脚本入口：
```powershell
.\plugins\cell_gd\skills\cell_gd\scripts\run_cell_gd.ps1 -InputImage .\original.png -OutputRoot .\output -Application ppt
```
把 `ppt` 改为 `ai` 选择 Illustrator。需要自定义放置、批次或续画时，使用各分支原运行脚本。已认可的 SVG 可直接进入后处理。

macOS PPT：
```bash
python plugins/cell_gd/skills/cell_gd/scripts/run_from_image.py --input-image original.png --output-root output
```

源码仓库：[yrui-cmd/cell-lct](https://github.com/yrui-cmd/cell-lct)。

## 余额显示

每次图片识别完成后自动显示服务端返回的剩余额度，例如 `剩余额度：20`；余额为零显示 `剩余额度：0`。接口未提供有效余额时显示 `剩余额度：暂不可用`。Windows 的 PPT、Illustrator 和 macOS 图片入口均显示该信息，不额外发起计费请求。该数值是本次识别完成时的额度快照。
