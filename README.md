# CutTools · 视频整理与交付

原生 SwiftUI macOS 应用，要求 macOS 14+、Xcode 命令行工具。本地构建：

```sh
./script/build_and_run.sh
```

应用位于 `dist/CutTools.app`。如果在受限的自动化沙箱内启动时报 Launch Services -10827，可从 Finder 双击应用；这次已通过桌面启动并查看原生窗口。

## 音乐卡点（新增）

打开应用默认进入音乐卡点。导入 MP3/WAV/M4A 或带音轨的视频，点击分析节拍；算法在本机计算频谱突变、低频瞬态与能量变化，不需要 AI 模型。单次分析最长 30 分钟。

波形支持缩放和点击/拖动定位；播放时按 M 添加手动标记。点击候选时间从前方 0.3 秒试听；可逐帧微调、禁用或删除标记。强拍只是较强瞬态候选，能量转折候选默认禁用；BPM 是相邻候选间隔估计，可能出现半速/倍速，不能据此认定小节首拍。

导出 FCPXML 会创建带原音乐素材和标记的新时间线，需保留原音乐路径；默认 25 fps，可改为 24/30/50/60 fps。标记对齐所选帧率、排除禁用点，同帧标记合并。也支持 CSV 时间表与 JSON 标记工程保存/恢复；JSON 不包含音频和波形。恢复工程后重新分析会替换标记，执行前会确认。

FCPXML 标记结构参考 [Apple 标记说明](https://developer.apple.com/documentation/professional-video-applications/associating-ratings-keywords-markers-and-metadata-with-media)。XML 结构和帧边界测试通过，但尚未在 Final Cut Pro 内完成兼容验收。当前支持整数帧率；23.976/29.97/59.94 需要后续补充。

## 卡点筛选与从零写稿（新增）

卡点可按强拍、能量转折、强拍与转折、手动类型筛选；列表和波形同步显示。筛选不改变启用状态。使用「批量保留」可只启用指定类型，其他类型（包括手动点）会禁用但保留；可以撤销上一次批量操作。FCPXML/CSV 始终导出全部启用点，与当前显示筛选无关。恢复标记工程后可「恢复波形（保留标记）」，无需重新生成标记。

「从零写稿」填写主题、受众、目标时长、目的、风格和事实素材，使用本机 Ollama 生成多个开头与完整的口播、镜头建议和屏幕文字。可选择模型、检查服务连接。只有成功且结构有效的结果才替换旧稿；失败或取消保留旧稿，再次生成会先确认。事实不足处要求模型使用待补充标记，生成内容仍需人工核实。

草稿与需求自动保存在本机；支持 Markdown 导出、复制口播稿、JSON 工程保存和载入。口播时长按每秒约 3.5 字估算，实际以朗读为准。未安装本地模型时可生成写作提纲，方括号内容需要自己填写，不会伪装成 AI 初稿。AI 写稿接口通过本地与在线请求模拟测试，尚未用真实模型验收生成质量。

## 本地与在线模型 / 应用图标（新增）

通过 macOS 菜单「CutTools → Settings…」（快捷键 ⌘,）或写稿/翻译工作区的「模型与 API Key 设置」进入统一配置。翻译与写稿共用当前模型，切换服务商后分别记住各自的地址与模型名称：

- Ollama：本机 `/api/generate`，无需 API Key，沿用原先的本地模型名。
- DeepSeek：预设 `https://api.deepseek.com`、`deepseek-flash`；可按账号权限改模型。
- 千问：预设北京通用地址 `https://dashscope.aliyuncs.com/compatible-mode/v1`、`qwen-plus`。可换控制台提供的业务空间专属/地域地址，Key 必须匹配地域。请求关闭混合思考，以获得普通文本 JSON 输出。
- 豆包：预设 `https://ark.cn-beijing.volces.com/api/v3`；填写火山方舟控制台的模型名或推理接入点 ID。
- 其他兼容接口：填写 HTTPS Base URL、模型与 Key，使用 Chat Completions 协议。

输入 API Key 后点击「保存 API Key」，密钥存储于系统钥匙串，按服务商与完整 Base URL 隔离，不写入偏好、文案/字幕或导出工程。编辑地址后需要重新保存对应 Key。在线生成会将待处理文本发送至设置中的地址，可能产生费用；不会自动上传音视频。在线连接测试也会发送一条短模型请求。

可选 JSON 模式仅适用于支持 `response_format=json_object` 的模型，默认不强制开启。仅支持非流式文本 Chat Completions；仅流式模型及 Responses-only 接口不适用。支持清除代码围栏、识别空结果/截断、鉴权/额度错误和取消，不会在失败时提交不完整译文或覆盖旧稿。在线请求禁止 HTTP 与重定向。

图标源文件在 `Assets/AppIcon.png`，包含音频波形和卡点标记；完整 iconset 与 `AppIcon.icns` 同目录保存，构建脚本会复制到应用 Resources 并配置 Info.plist，启动时设置 Dock 图标。

接口预设参考 [DeepSeek 官方文档](https://api-docs.deepseek.com/)、[千问官方兼容接口](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[火山方舟官方 API Explorer](https://api.volcengine.com/api-explorer/?action=ChatCompletions&groupName=%E5%AF%B9%E8%AF%9D%28Chat%29+API&serviceCode=ark&tab=3&version=2024-01-01)。在线协议与错误处理已使用模拟响应验证，尚未使用真实 API Key 完成三家在线验收。

## 已实现

- 中英 SRT 导入、时间重叠匹配（一对多标记确认）、基础问题检查、编辑时间与文字、右键合并/拆分/删除、整体偏移、独立 SRT 导出。
- 原视频预览、保留/裁切/原比例导出、模糊背景、水平裁切位置、三处采样黑边建议、个人交付预设、避免覆盖、任务取消。
- 创作与检查 → AI 字幕：Whisper.cpp 本地转写，Ollama 中英翻译、术语表；失败或取消不会提交不完整译文。转写成功会替换对应语言轨。
- 双语字幕分别设置字号与颜色、间距、底边距离；ASS 导出与烧录；基础 FCPXML 可编辑标题时间线导出。
- 口播粗剪：长静音、字幕中的独立口头禅和相邻相同句候选；手动勾选删除、点击文字定位、重新编码导出，并重算中英字幕时间。长静音默认保留两端 0.15 秒。
- 成片检查：黑场、静音、音频满幅峰值风险、字幕超时及可能换行提示；定位与文本报告导出。检测结果均需人工确认。

## 本地依赖

FFmpeg 从 `/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin` 查找。烧录需要 `subtitles` 滤镜及 libass，当前本机版本不包含该滤镜，应用会明确提示；可以先导出 ASS。

转写需要自行安装 [Whisper.cpp](https://github.com/ggml-org/whisper.cpp) 并下载 ggml 模型，再在 AI 工作区选择 `whisper-cli` 和模型文件。根据源语言选择中文或英文。

翻译和写稿均可选本地 Ollama 或在线模型，详见上方统一模型配置。Ollama 需要安装并下载本地模型，应用不会自动下载；在线模式需要提供对应服务的 API Key。

## 验证与限制

`swift test --disable-sandbox` 包含字幕解析、匹配、区间合并、字幕时间重算、检测日志、ASS 转义与实际 FFmpeg 黑场/静音分析和粗剪导出测试。

已验证编译和原生窗口。Whisper/Ollama 未在本机安装，尚未完成真实模型端到端验收。FCPXML 为基础标题模板，当前沿用中文字号和白色，不承诺不同 FCP 版本导入兼容；需在目标 Final Cut Pro 中确认。ASS 支持独立中英样式。

仍待补齐第一版细节：手动重新配对、逐项修复及前后对比、实时导出百分比与体积估算、失败重试。视频播放窗口显示原视频；10 秒导出预览用于核对实际适配和烧录结果。批量导出将同一字幕轨应用于所有输入视频；不同视频请分别处理。粗剪先重编码各段再合并，切点精度受帧率和音频帧边界影响。字幕溢出提示是文字长度估算，不是逐像素检测。
