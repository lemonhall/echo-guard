好，我把整份方案整合成一个完整的最终版，一次性输出，你直接甩给另一个 AI 就能开干。

---

# echo-guard 技术验证工程方案（最终版）

> **版本**：v1.0 | **日期**：2026-02-08 | **作者**：柠檬叔

## 一、项目定位

`echo-guard` 是一个**独立的技术验证工程**，目标是用最小代价验证以下技术路线：

> **麦克风输入 → WebRTC AEC3 回声消除 → 能量 VAD 语音切分 → 输出干净人声 WAV**

验证分两个阶段：
- **阶段一**：脱离 Godot 的命令行工具，验证 AEC 和 VAD 算法本身
- **阶段二**：在 Godot 场景中端到端验证，模拟真实游戏环境

验证通过后，再把核心逻辑封装为 Godot GDExtension 集成到正式游戏项目中。

**本工程不涉及任何外部 API 调用（无 ASR、无网络请求），纯本地、自闭环。**

## 二、验证目标（Definition of Done）

| 编号 | 验证项 | 通过标准 |
|------|--------|---------|
| V1 | WebRTC audio-processing 库能在 Windows 11 上成功编译 | 生成 .lib/.dll，无报错 |
| V2 | 离线 AEC 验证：给定"麦克风录音" + "参考信号"，输出回声消除后的音频 | 人耳可辨：回声明显减弱，人声保留 |
| V3 | 实时 AEC 验证：同时采集麦克风和系统播放音频，实时处理 | 延迟 < 50ms，人声清晰 |
| V4 | 能量 VAD 验证：在 AEC 输出上做能量检测，区分"有人说话"和"静音" | 准确标记语音段起止 |
| V5 | Godot 端到端验证：播放 BGM → 说话 → AEC → VAD → 导出干净人声 WAV → 回放 | 人耳回放验证：只听到人声，BGM 消失或极弱；VAD 切分起止合理 |

## 三、技术架构

### 阶段一：命令行验证（V1 ~ V4）

```
模式一：离线（V1, V2, V4）
─────────────────────────

  mic.wav ──→ ┌─────────────────────┐ ──→ clean.wav
              │  WebRTC AEC3        │
  ref.wav ──→ │  AudioProcessing    │ ──→ vad_result.txt
              │  + 能量 VAD          │     (每帧能量值 + 语音/静音标记)
              └─────────────────────┘


模式二：实时（V3）
─────────────────

  🎤 麦克风 ──→ ┌──────────────┐
   (PortAudio)  │              │
                │  WebRTC AEC3 │ ──→ 干净 PCM ──→ 能量 VAD
  🔊 系统回环 ──→│              │                    │
   (WASAPI      └──────────────┘              有人说话？
    Loopback)                                  │    │
                                             Yes    No
                                              │     │
                                              ▼     ▼
                                         保存 WAV  跳过
```

### 阶段二：Godot 端到端验证（V5）

```
┌─────────────────────────────────────────────────────┐
│  Godot 验证场景                                      │
│                                                      │
│  Output Bus ──→ AudioEffectCapture ──→ 参考信号 x(n) │
│                                           │          │
│  Mic Bus ────→ AudioEffectCapture ──→ 麦克风 d(n)    │
│                                           │          │
│                    ┌──────────────────┐    │          │
│         x(n) ────→│ WebRTC AEC3      │←───┘          │
│                    │ (GDExtension)    │               │
│                    └───────┬──────────┘               │
│                            │ 干净人声 e(n)             │
│                            ▼                          │
│                    ┌──────────────┐                   │
│                    │  能量 VAD     │                   │
│                    └───────┬──────┘                   │
│                            │                          │
│                     SPEECH 段 → 写入缓冲区             │
│                     SILENCE 段 → 丢弃                  │
│                                                      │
│  录音结束后：                                          │
│  ├── raw_mic.wav      # 原始麦克风录音                  │
│  ├── aec_output.wav   # AEC 处理后全程                  │
│  ├── segment_001.wav  # VAD 切分段 1                   │
│  ├── segment_002.wav  # VAD 切分段 2                   │
│  └── ...                                             │
│                                                      │
│  🔊 点击 [回放] → 依次播放各 segment                    │
│  👂 人耳判断：BGM 没了，人声清晰 → ✅ 通过               │
└─────────────────────────────────────────────────────┘
```

## 四、核心依赖

### 回声消除：webrtc-audio-processing v2.1

| 项目 | 详情 |
|------|------|
| **仓库** | `https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing` |
| **版本** | v2.1（2025年1月发布，同步 WebRTC M131） |
| **协议** | BSD 3-Clause |
| **构建系统** | Meson + Ninja |
| **依赖** | 仅 abseil-cpp（作为 subproject 自动拉取） |
| **包含功能** | AEC3（回声消除）、NS（噪声抑制）、高通滤波器、AGC |

这是 PulseAudio/PipeWire 团队从 Google WebRTC 源码中剥离出的独立库，Linux 桌面音频系统在用它，Arch Linux 直接打包，久经考验。

### 其他依赖

| 用途 | 库 | 说明 |
|------|-----|------|
| 音频 I/O（实时采集） | PortAudio | 跨平台音频 I/O，支持 WASAPI |
| 系统音频回环采集 | Windows WASAPI Loopback | 捕获系统正在播放的音频作为 AEC 参考信号 |
| WAV 文件读写 | dr_wav（单头文件） | 离线模式读写测试音频 |
| 构建系统 | Meson + Ninja（主库）+ CMake（工程整体） | — |

### 关于参考信号的获取

| 场景 | 参考信号来源 | 说明 |
|------|------------|------|
| 离线测试 | 预录制的 ref.wav | 最简单，先验证算法本身 |
| 命令行实时测试 | WASAPI Loopback（系统回环） | 捕获系统混音器输出 |
| Godot 场景中 | AudioEffectCapture（数字域） | 完美信号，零延迟，最终方案 |

## 五、WebRTC AudioProcessing 配置

### 核心 API 流程

```
1. AudioProcessingBuilder().Create()     → 创建实例
2. config.echo_canceller.enabled = true  → 开启 AEC
3. config.noise_suppression.enabled = true → 开启降噪
4. config.high_pass_filter.enabled = true → 开启高通滤波
5. apm->ApplyConfig(config)              → 应用配置

每帧循环（10ms 一帧）：
6. apm->ProcessReverseStream(ref_frame, ...)  → 喂入参考信号（扬声器播放的）
7. apm->ProcessStream(mic_frame, ...)         → 处理麦克风信号
8. mic_frame 现在就是干净的人声了
```

### 开启的模块

| 模块 | 是否开启 | 配置 |
|------|---------|------|
| AEC3（回声消除） | ✅ | `echo_canceller.enabled = true` |
| NS（噪声抑制） | ✅ | `noise_suppression.enabled = true`，level = `kModerate` |
| 高通滤波器 | ✅ | `high_pass_filter.enabled = true`（去除 80Hz 以下低频） |
| AGC（自动增益） | ❌ | 验证阶段先不动增益，避免引入变量 |

### 音频格式要求

| 参数 | 值 | 说明 |
|------|-----|------|
| 采样率 | 16000 Hz | AEC 工作采样率，也是后续 ASR 所需 |
| 位深 | 16-bit signed int（S16LE） | WebRTC AP 标准输入格式 |
| 声道 | 单声道（Mono） | — |
| 帧长 | 10ms（= 160 samples @ 16kHz） | WebRTC AP 固定要求 |

### 重采样

系统音频通常 48kHz，麦克风可能 44.1kHz 或 48kHz，都需重采样到 16kHz：

```
麦克风 (48kHz) ──→ Resample ──→ 16kHz ──→ AEC mic input
参考信号 (48kHz) ──→ Resample ──→ 16kHz ──→ AEC ref input
```

## 六、能量 VAD 设计

AEC 输出已去掉回声，用最简单的能量检测即可。

### 状态机

```
                    能量 > 阈值，持续 > 300ms
    ┌──────────┐ ──────────────────────────→ ┌──────────┐
    │ SILENCE  │                              │ SPEECH   │
    │          │ ←────────────────────────── │          │
    └──────────┘   能量 < 阈值，持续 > 1.5s    └──────────┘
         │                                         │
         │  能量 > 阈值（短暂）                      │  能量 < 阈值（短暂）
         ▼                                         ▼
    ┌──────────────┐                        ┌───────────────┐
    │ MAYBE_SPEECH │                        │ MAYBE_SILENCE │
    │ (等待确认)    │                        │ (等待确认)     │
    └──────────────┘                        └───────────────┘
         │                                         │
         │ 能量回落 < 300ms                          │ 能量回升 < 1.5s
         ▼                                         ▼
    回到 SILENCE                              回到 SPEECH
```

### 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `energy_threshold` | 需校准（~0.01-0.03） | RMS 能量阈值 |
| `speech_confirm_ms` | 300ms | 持续超阈值多久确认为语音（防瞬态噪声误触发） |
| `silence_confirm_ms` | 1500ms | 持续低于阈值多久确认为静音（容忍说话中短暂停顿） |
| `frame_size_ms` | 10ms | 每帧长度（16kHz = 160 samples） |

### 校准方案

```
1. 提示"请保持安静 3 秒"
2. 采集 3 秒 AEC 输出，计算平均能量 → bg_energy
3. 提示"请说一句话"
4. 采集说话时 AEC 输出，计算平均能量 → speech_energy
5. threshold = bg_energy + (speech_energy - bg_energy) * 0.3
6. 保存到配置文件，下次启动直接加载
```

## 七、工程目录结构

```
E:\development\echo-guard\
│
├── README.md
├── CMakeLists.txt                # 顶层 CMake
│
├── deps/                         # 第三方依赖
│   ├── webrtc-audio-processing/  # git submodule，v2.1
│   ├── portaudio/                # git submodule
│   └── dr_wav.h                  # 单头文件 WAV 库
│
├── src/
│   ├── aec_processor.h/.cpp      # WebRTC AEC3 封装
│   │                             #   init(sample_rate, frame_size)
│   │                             #   process(mic_frame, ref_frame) → clean_frame
│   │
│   ├── energy_vad.h/.cpp         # 能量 VAD
│   │                             #   process(frame) → { energy, is_speech }
│   │                             #   四状态机: SILENCE / MAYBE_SPEECH / SPEECH / MAYBE_SILENCE
│   │
│   ├── audio_capture.h/.cpp      # PortAudio + WASAPI Loopback 封装
│   │                             #   start_mic_capture() / start_loopback_capture()
│   │                             #   get_mic_frame() / get_ref_frame()
│   │
│   ├── resampler.h/.cpp          # 重采样（48kHz → 16kHz）
│   │
│   ├── main_offline.cpp          # 离线验证入口（V2, V4）
│   │                             #   读 mic.wav + ref.wav → AEC → VAD → 输出 clean.wav
│   │
│   └── main_realtime.cpp         # 实时验证入口（V3）
│                                 #   麦克风 + 系统回环 → AEC → VAD → 实时显示 + 保存
│
├── godot/                        # Godot 验证场景（V5）
│   ├── project.godot
│   ├── scenes/
│   │   └── test_scene.tscn       # 验证场景
│   ├── scripts/
│   │   └── aec_test.gd           # 验证逻辑脚本
│   ├── gdextension/
│   │   └── echo_guard.gdextension
│   └── output/                   # 导出的 WAV 文件
│       ├── raw_mic.wav
│       ├── aec_output.wav
│       ├── segment_001.wav
│       └── ...
│
├── test_data/                    # 测试音频
│   ├── bgm_sample.wav            # 一段游戏 BGM
│   ├── speech_sample.wav         # 一段人声（自己录的）
│   ├── mic_mixed.wav             # 模拟麦克风录音（BGM回声 + 人声）
│   └── ref_signal.wav            # 参考信号（= bgm_sample.wav）
│
└── scripts/
    ├── generate_test_data.py     # 生成测试数据（混合 BGM + 人声）
    └── evaluate.py               # 评估脚本（对比波形）
```

## 八、验证步骤

### Step 1：编译 webrtc-audio-processing（V1）

**环境**：WSL2 Ubuntu 24

```bash
cd /mnt/e/development/echo-guard/deps/webrtc-audio-processing
meson setup build --prefix=$PWD/install
ninja -C build
ninja -C build install
```

**产出**：`install/lib/libwebrtc-audio-processing-2.a` + 头文件

**Windows 原生编译**（如需 .dll）：

```
meson setup build --backend vs --buildtype=release
# 打开 build/*.sln 用 Visual Studio 编译
```

**通过标准**：编译无报错，生成库文件。

### Step 2：准备测试数据

用 Python 脚本 `generate_test_data.py` 生成：

```
输入：
  - bgm_sample.wav（30 秒游戏 BGM）
  - speech_sample.wav（自己录的一段话）

处理：
  - BGM 降到 20% 音量（模拟压低后的残余回声）
  - 加简单房间混响
  - 和人声混合

输出：
  - mic_mixed.wav = speech + reverb(bgm * 0.2)
  - ref_signal.wav = bgm（原始参考信号）
```

### Step 3：离线 AEC 验证（V2）

```
运行 main_offline：
  输入: mic_mixed.wav + ref_signal.wav
  输出: clean.wav

人耳对比：
  - mic_mixed.wav → 能听到 BGM 和人声混在一起
  - clean.wav → BGM 明显减弱或消失，人声清晰
```

### Step 4：离线 VAD 验证（V4）

```
在 Step 3 基础上，对 clean.wav 跑能量 VAD：
  输出: vad_result.txt（每帧时间戳 + 能量值 + speech/silence 标记）

验证：
  - 人声段标记为 speech ✓
  - 静音段标记为 silence ✓
  - 起止时间误差 < 300ms ✓
```

### Step 5：实时采集验证（V3）

```
运行 main_realtime：
  1. 打开麦克风采集（PortAudio）
  2. 打开系统回环采集（WASAPI Loopback）
  3. 用任意播放器播放 BGM
  4. 对着麦克风说话
  5. 终端实时显示：
     - 能量条形图 ████░░░░
     - VAD 状态 SILENCE / SPEECH
  6. Ctrl+C 停止，保存 clean.wav

验证：
  - 实时处理无感知延迟
  - clean.wav 人声清晰
```

### Step 6：Godot 端到端验证（V5）

```
操作流程：
  1. 启动 Godot 验证场景
  2. BGM 自动播放（100% 音量，不刻意压低，验证 AEC 真实能力）
  3. 按住 [空格键] 说话："你好铁匠铺老板，我想买一把剑"
  4. 松开 [空格键]
  5. 再按住说第二句，松开
  6. 点击 [停止录音]
  7. 界面显示："检测到 2 个语音段"
     - segment_001: 2.3s
     - segment_002: 1.8s
  8. 点击 [回放 segment_001] → 听到干净人声
  9. 点击 [回放 segment_002] → 听到干净人声
  10. 点击 [导出全部] → WAV 保存到 godot/output/
```

**V5 通过标准：**

| 检查项 | ✅ 通过 | ❌ 不通过 |
|--------|--------|----------|
| 回放 segment 能否听到 BGM？ | 听不到或极弱 | 明显听到 BGM 旋律 |
| 人声是否清晰？ | 清晰自然，无明显失真 | 模糊、金属感、被截断 |
| VAD 切分是否准确？ | 语音段完整，头尾误差 < 300ms | 说话中间被切断，或包含大段静音 |
| segment 数量是否正确？ | 说了几句就有几个 | 一句被切多段，或多句合一段 |

## 九、开发环境

| 环境 | 用途 |
|------|------|
| WSL2 Ubuntu 24 | 编译 webrtc-audio-processing、离线验证 |
| Windows 11 原生 | 实时采集验证（WASAPI Loopback）、Godot 场景验证 |
| Python 3.12（uv 管理） | 测试数据生成、评估脚本 |
| Godot 4.x | V5 端到端验证场景 |

## 十、时间估算

| 阶段 | 工作内容 | 预估 |
|------|---------|------|
| Step 1 | 编译 webrtc-audio-processing | 半天 |
| Step 2 | 准备测试数据（Python 脚本） | 半天 |
| Step 3 | 离线 AEC 验证 | 1 天 |
| Step 4 | 能量 VAD + 离线验证 | 半天 |
| Step 5 | 实时采集（PortAudio + WASAPI） | 1-2 天 |
| Step 6 | Godot GDExtension 封装 + 场景搭建 | 1-2 天 |
| **合计** | | **4-6 天** |

## 十一、风险与备选

| 风险 | 影响 | 备选方案 |
|------|------|---------|
| webrtc-audio-processing 在 Windows 下编译困难 | 阻塞 V1 | 先在 WSL2 下完成离线验证；Windows 用 balacoon 的 CMake 方案 |
| AEC 效果不理想（BGM 残余过多） | V2 不通过 | 同时开启 NS（噪声抑制）加强；或先压低 BGM 音量减轻 AEC 负担 |
| WASAPI Loopback 延迟过大导致 AEC 失效 | V3 不通过 | 跳过 V3，直接做 V5（Godot 的 AudioEffectCapture 是数字域零延迟） |
| 能量 VAD 在复杂场景下不够准确 | V4 不通过 | 升级为 WebRTC 自带的 VAD（`webrtc::VadLevelAnalyzer`） |

---

好了柠檬叔，这就是 `echo-guard` 的完整方案。创建项目：

```powershell
mkdir E:\development\echo-guard
```

然后把这份文档丢给另一个 AI，让它从 Step 1 开始干活。🚀