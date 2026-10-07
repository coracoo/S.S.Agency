# 第一夜石钵：可选本地过场

## 放置文件

开发工程固定路径：

```text
项目根/assets/cutscenes/night1_stone_bowl.ogv
Godot路径：res://assets/cutscenes/night1_stone_bowl.ogv
```

文件由用户从LibTV下载并转换后自行放入。代码不访问LibTV、不联网播放、不下载视频。此目录忽略媒体文件，不把正式视频或测试视频提交到GitHub；没有文件时游戏照常运行。

**只支持Ogg容器中的Theora视频，声音用Vorbis。MP4/H.264、H.265、WebM不能直接交给当前内置播放器；仅改扩展名无效。** 本机官方Godot `4.7.2.stable.official.ed1daf0bf` 的ClassDB实际返回 `VideoStreamTheora`，VideoStream可识别媒体扩展为 `ogv`（`tres`/`res`是资源容器）。无需播放器插件。

已批准的片段是第一夜石钵15秒/720p，内容覆盖现有h1/h2：

- 凛音：「停。薄荷，看台阶边上那尊石钵——水面上有光。」
- 薄荷：「冷冷的……蓝紫色的。可是凛音，那倒影里——没有我们。」

## 转换为可播放格式

准备带 `libtheora`、`libvorbis` 编码器的FFmpeg。在工程根目录运行以下命令，输入文件名按实际下载的文件修改；输出目录已在仓库内保留。命令适用于单行的Windows PowerShell/CMD与常见Unix shell。

```sh
ffmpeg -i "night1_stone_bowl.mp4" -map 0:v:0 -map "0:a:0?" -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1" -r 30 -c:v libtheora -q:v 7 -g:v 64 -pix_fmt yuv420p -c:a libvorbis -q:a 6 -ar 48000 -ac 2 "assets/cutscenes/night1_stone_bowl.ogv"
```

此命令输出1280×720、30fps、Theora/yuv420p、Vorbis立体声48kHz，保持画幅比例并加黑边，保留原片完整时长。可选音轨映射允许无音轨源正常转换；有声音的最终片应保留对白声音。没有使用 `-y`，已有同名文件会由FFmpeg提示是否覆盖。

核对输出音视频编码与时长：

```sh
ffprobe -v error -show_entries stream=codec_name,codec_type,width,height,pix_fmt,r_frame_rate,sample_rate,channels:format=duration -of json "assets/cutscenes/night1_stone_bowl.ogv"
```

应看到 `theora`、1280×720、`vorbis`、2声道以及约15秒。最终片尚未由本次代码任务下载或验收，用户放入后应按下节预览。

## 预览与剧情接续

在Godot编辑器打开 `scenes/preview/night1_cutscene.tscn`，按 **F6**。此入口只预览文件，不创建主线会话，不读写正式存档；结束或Esc后显示结果，重新F6可重播。缺片/不可读文件显示放置路径。也可从工程根执行：

```sh
godot --path . res://scenes/preview/night1_cutscene.tscn
```

正式游戏仍从原标题进入 `scenes/campaign/night_1.tscn`。完成原开场、走到石钵调查点，按E「察看水钵倒影」才会尝试播放；不会在标题/出生/尚未抵达时播放。

- 正常播完：从原h3「石钵照的不是人……」继续，保留原选择分支与后文。
- Esc：主动跳过片段及其覆盖的h1/h2，从h3继续。Esc被当前播放器消费，不打开暂停菜单。
- 未放片、格式错误、截断文件、启动失败或播放中断：从原h1开始完整对白。
- 片段不循环，期间暂时锁住探索并暂停已有游戏音频；结束、跳过、故障或退出场景均恢复进入前的暂停/音频状态。视频音量沿用Master总线，不改用户音量设置。
- 视频本身不保存、不发奖励、不完成调查。只有后续原对白真正结束，才经原 `ChapterSession.commit_event` 保存 `dialogue:h1`。连按、重复结束信号和Esc/结束同帧不会重复提交。
- 已完成石钵事件的存档不会强制重播。想单独看视频用F6预览；不必覆盖自己的存档。片段中退出后，该调查仍未完成，重新加载可再次调查。

## 导出包旁的外置文件

独立导出EXE支持：

```text
游戏目录/
  游戏.exe
  游戏.pck                 （或嵌入EXE的PCK）
  cutscenes/
    night1_stone_bowl.ogv
```

运行官方Godot引擎加独立PCK时，把 `cutscenes` 放在PCK/发布启动器旁，使用已有 `launch_campaign.bat` / `launch_campaign.sh`。它们会先进入发布目录，外置片段按该工作目录读取。手动启动应先进入PCK所在目录，再执行：

```sh
godot --main-pack ssa-seven-chapter-formal.pck
```

Godot会从 `OS.get_cmdline_args()` 删除 `--main-pack`，因此不能依赖该API反推任意PCK文件的所在目录。不要在别的工作目录用绝对PCK路径启动后期待自动找到它旁边的片段。

独立EXE优先读取EXE旁的 `cutscenes`；独立PCK启动器读取工作目录的 `cutscenes`；最后可读已打包的 `res://assets/cutscenes`。当前发布工具不会自动把这个可选大视频加入PCK，推荐上述外置方式。播放器与配置为主场景静态preload依赖，正常随代码发布；未更改CI或正式视频打包策略。

## 验收与限制

运行隔离检查（需本机Godot4.7.2与FFmpeg）：

```sh
python3 tools/campaign/run_cutscene_checks.py --godot /absolute/path/to/godot --import-lock /absolute/path/to/godot-import.lock
```

入口先验证引擎实际 `user://` 位于临时目录，随后在仓库外生成1.5秒、160×90、Theora+Vorbis技术色块夹具。它不代表最终美术，不上传，也不会放入正式路径。

已验：真实解码时间推进/自然结束、不循环、Esc与结束同帧/连按、缺文件/坏文件/截断文件/中段损坏或整页丢失/缺流结束标志/停流回退、预先暂停状态、已有音频状态、场景离树、h1/h3接续、原分支和末句、保存时机及重新读档。1.5秒和4秒片段的3FPS真实壁钟播放另有窄测；结束位置使用实际UI帧间隔及Theora头中FRN/FRD表示的视频帧时长，不采用固定帧率假设或放大的固定尾部容差。另用极小PCK验证外置文件路径，覆盖绝对与相对 `--main-pack` 启动。原主线状态/双形态/世界动作回归一并检查。

原生桌面自动夹具已在Compatibility/OpenGL中读回并检查实际色块/计时画面及Esc提示，保持原片比例。可在已连接的桌面终端对检查命令添加 `--graphical --output-dir /仓库外/证据目录` 重跑；图形检查使用Dummy音频设备，不代表人工听音验收。

尚未验收最终LibTV片的画面、口型和声音；本机没有生成独立Windows EXE，因此不把PCK路径测试称作Windows成品验收。Theora为CPU解码，正式片建议720p/30fps。加载器预检Ogg页CRC、逐流页序与结束标志；异常停流超过4秒自动回退，片段最大120秒。

参考Godot官方：[视频播放与格式](https://docs.godotengine.org/en/latest/tutorials/animation/playing_videos.html)、[VideoStreamTheora](https://docs.godotengine.org/en/latest/classes/class_videostreamtheora.html)、[VideoStreamPlayer](https://docs.godotengine.org/en/latest/classes/class_videostreamplayer.html)；帧时长字段依据[Xiph Theora规范第6.2节](https://www.theora.org/doc/Theora.pdf)。latest文档可能包含未发布特性，本项目格式判断以本机4.7.2实测为准。
