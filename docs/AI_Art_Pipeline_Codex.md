# 当前素材制作与复用工作流

> 更新：2026-09-30。适用《逢魔退治帖》日式水彩绘本版本。
> [旧管线原文](archive/2026-09-30-before-v4/docs/AI_Art_Pipeline_Codex.md)仅供历史复现。

1. 先查现有背景、人物、卡面、UI 与动画；确认确实存在内容缺口。
2. 按 [美术规范](Art_Bible.md) 和当前实际成品选参考，不再强制走旧蒸汽朋克 manifest。
3. 将任务关联到具体案件、卡牌或界面；记录目标路径、透明需求、尺寸、锚点、配置入口。
4. 使用当前可用且已授权的图像工具制作；单张风格确认后再做同批扩展。
5. 校验文字、轮廓、透明边缘、脚点、动画帧一致性与画风；不合格回到源图修正。
6. 通过现有导入和资源加载路径接入，检查实际场景与导出包，不只看孤立素材。

参考风格描述：hand-painted watercolor storybook, Japanese folk twilight, washi paper grain, warm ochre and paper white, soft diffused light, consistent painterly characters, restrained vermilion and kintsugi accents。

这只是风格说明，不绑定旧批处理脚本或过时的工具型号。生成图片中的占位文字由界面排版提供，避免将乱码作为正式文本。

现有目录继续使用 `assets/bg/`、`assets/chars/`、`assets/ui/`、`assets/effects/` 与 `assets/audio/`；不要为文档里的旧目录命名批量搬迁资源。

旧 `tools/gen_steampunk_assets.py` 及其 manifest 保留给旧版本复现，不自动执行，不作为当前新素材默认入口。本次没有生成、改写或搬迁素材。
