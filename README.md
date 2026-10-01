# Anima Editor 赋灵 编辑器

[English](#english) · [中文](#中文)

A cross-platform editor for **creating and editing deformable 2D character models** — parts,
deformers, keyforms, physics, motions and expressions. Built with Flutter; runs on Windows,
Linux, macOS, Android, iOS and the web from one codebase.

面向**可变形 2D 角色模型**的创建与编辑工具：部件、变形器、关键形、物理、动作与表情。
基于 Flutter，同一套代码跑 Windows、Linux、macOS、Android、iOS 与 Web。

---

## 中文

### 这是什么

赋灵编辑器是这个项目里**负责制作**的一端。它让你从零搭出一个可变形 2D 角色：切部件、
绑变形器、拉关键形、调物理、编动作与表情，最后存成 `.amproj` 工程文件。
配套的**查看器**负责播放与分发，两者共用同一份引擎契约。

编辑器**不自己实现模型与求值** —— 所有结构改动都走引擎的命令系统，这样撤销栈、
画面上的结果、存盘的文件三者不会互相打架。

### 功能

| 面板 | 做什么 |
| --- | --- |
| 画布 | 交互绘制与命中测试，洋葱皮，缩放平移、翻转、网格与参考线 |
| 层级 | 部件树，拖拽调整父子关系与顺序 |
| 参数 | 定义参数与取值范围，驱动关键形混合 |
| 检视器 | 选中对象的属性编辑 |
| 网格 | 部件顶点编辑 |
| 变形器 | 弯曲与旋转变形器，级联关系 |
| 关键形 | 绑定到参数的关键形编辑与插值预览 |
| 时间轴 | 动作编辑、播放头、帧操作 |
| 曲线 | 参数动画曲线编辑 |
| 物理 | 摆动与顶点链物理设置 |
| 表情 | 表情定义与快捷键绑定 |
| 姿态 | 姿态管理 |
| 口型同步 | 音量驱动的口型参数映射 |
| 模型设置 | 模型级参数与元信息 |
| 校验 | 工程校验结果与最近导出哈希 |
| 历史 | 操作历史与撤销栈 |
| 性能 | 后端、引擎版本、统计与能力探测 |

其它：

- **17 个可停靠面板**，四区域布局，拖拽换区，尺寸与显隐自动保存。
- **中英双语界面**，跟随系统或手动切换。
- **深色优先的主题**，可切换浅色与跟随系统。
- **快捷键注册表**，新建/打开/保存/导出/撤销重做/视图/播放等均可键控。
- **引擎自动降级**：引擎库缺失或加载失败时退回内置实现，界面**不崩溃、不白屏**，
  只在通知栏给出可读提示。

### 平台

Windows · Linux · macOS · Android · iOS · Web

### 工程格式

`.amproj` 有两种形态，同一份内容：

- **目录模式**：`info.json`、`registry.json`、`assets/`、`metadata/`、`spec/`。
- **归档模式**：ZIP + Deflate，条目限定在白名单前缀内。

导出会同时产出 `<名称>.amproj` 和伴生的 `<名称>.amproj.sha256`；导入时先解包再校验，
校验不过**回滚**删除目标目录。解析会拒绝绝对路径与 `..`，防止 ZIP_SLIP。

### 快速开始

需要 Flutter 3.44 或更高版本。

```bash
flutter pub get
flutter run -d windows      # 或 linux / macos / chrome
```

构建产物：

```bash
flutter build windows --release
flutter build apk --release
flutter build web --release
```

### 引擎

编辑器通过 `AmEngine.call(method, params)` 这一个入口访问引擎，**没有第二个调用通道**。
真实引擎的方法面与界面所需不同，差异全部在 `core/engine/contract_am_engine.dart`
这一层翻译。

引擎库从哪来，有两条路：

- **什么都不配**（推荐）：构建时自动去引擎仓库的 Releases 里找本平台产物 ——
  从最新版往回找，最多看 5 个版本，取第一个带本平台产物的；都没有就跳过注入，
  产物退回内置实现，构建**不会失败**。
- **钉死地址**：配 `ENGINE_<平台>_URL` 环境变量，就只用这个地址，不再自动回退。

细节见 [`docs/build-and-release.md`](docs/build-and-release.md)。

### 开发

```bash
dart format lib test
flutter analyze
flutter test
```

i18n 键完整性校验（界面不许露出内部键名）：

```powershell
& .\tool\check_translations.ps1
```

仓库结构见 [`docs/architecture.md`](docs/architecture.md)，
引擎所需的方法面见 [`docs/engine-requests.md`](docs/engine-requests.md)。

### 已知限制

- macOS 产物**未签名、未公证**，在别的机器上会被 Gatekeeper 拦下。
- Android / iOS 的构建路径没有在开发机上本地验证过，首次跑请盯日志。
- 当前引擎 ABI 未导出共享纹理句柄，画布实际走降级画家（`CustomPaint`），
  而非零拷贝的 `Texture` 路径。
- 引擎地址需为**可匿名下载的直链**，私有仓库尚未支持。

### 许可

GNU Affero General Public License v3.0，见 [`LICENSE`](LICENSE)。

---

## English

### What it is

Anima Editor is the **authoring** half of this project. It lets you build a deformable 2D
character from scratch — cut parts, attach deformers, shape keyforms, tune physics, and
author motions and expressions — then save it as an `.amproj` project. The companion
**viewer** handles playback and distribution; both share one engine contract.

The editor does **not** implement the model or the evaluation itself. Every structural edit
goes through the engine's command system, so the undo stack, the on-screen result, and the
saved file can never disagree.

### Features

| Panel | What it does |
| --- | --- |
| Canvas | Interactive drawing and hit testing, onion skin, zoom/pan, flip, grid and guides |
| Hierarchy | Part tree; drag to reparent and reorder |
| Parameters | Define parameters and their ranges, driving keyform blending |
| Inspector | Property editing for the current selection |
| Mesh | Per-part vertex editing |
| Deformer | Warp and rotation deformers, and their cascading |
| Keyform | Keyform editing bound to parameters, with interpolation preview |
| Timeline | Motion editing, playhead, frame operations |
| Curve | Parameter animation curve editing |
| Physics | Pendulum and vertex-chain physics settings |
| Expressions | Expression definitions and hotkey bindings |
| Pose | Pose management |
| Lip sync | Amplitude-driven parameter mapping for mouth shapes |
| Model settings | Model-level parameters and metadata |
| Validation | Project validation results and the last export hash |
| History | Operation history and the undo stack |
| Performance | Backend, engine version, statistics and capability probing |

Also:

- **17 dockable panels** across four regions; drag to move between regions, with sizes and
  visibility persisted automatically.
- **Bilingual UI** (Chinese and English), following the system or set manually.
- **Dark-first theme** with light and follow-system options.
- **Shortcut registry** covering new/open/save/export, undo/redo, view, playback and more.
- **Automatic engine fallback**: if the engine library is missing or fails to load, the app
  drops back to a built-in implementation — the UI never crashes and never goes blank,
  showing only a readable notice.

### Platforms

Windows · Linux · macOS · Android · iOS · Web

### Project format

`.amproj` comes in two shapes holding the same content:

- **Directory mode**: `info.json`, `registry.json`, `assets/`, `metadata/`, `spec/`.
- **Archive mode**: ZIP + Deflate, with entries confined to a whitelist of prefixes.

Export writes `<name>.amproj` plus a companion `<name>.amproj.sha256`. Import unpacks first
and validates second, **rolling back** by deleting the target directory on failure. Parsing
rejects absolute paths and `..` to prevent ZIP_SLIP.

### Getting started

Requires Flutter 3.44 or later.

```bash
flutter pub get
flutter run -d windows      # or linux / macos / chrome
```

Release builds:

```bash
flutter build windows --release
flutter build apk --release
flutter build web --release
```

### The engine

The editor reaches the engine through exactly one entry point, `AmEngine.call(method, params)`
— there is **no second channel**. The real engine's method surface differs from what the UI
needs, and every difference is translated in `core/engine/contract_am_engine.dart`.

There are two ways to supply the engine library:

- **Configure nothing** (recommended): the build automatically looks for this platform's
  artifact in the engine repository's Releases — walking back from the newest release at
  most 5 versions and taking the first one that has this platform's artifact. If none does,
  injection is skipped and the build **still succeeds**, falling back to the built-in
  implementation.
- **Pin an address**: set an `ENGINE_<PLATFORM>_URL` environment variable and only that
  address is used, with no automatic fallback.

See [`docs/build-and-release.md`](docs/build-and-release.md) for details.

### Development

```bash
dart format lib test
flutter analyze
flutter test
```

i18n key completeness check (the UI must never leak internal key names):

```powershell
& .\tool\check_translations.ps1
```

Repository layout: [`docs/architecture.md`](docs/architecture.md).
Method surface required from the engine: [`docs/engine-requests.md`](docs/engine-requests.md).

### Known limitations

- macOS artifacts are **unsigned and unnotarized**, so Gatekeeper blocks them on other machines.
- The Android and iOS build paths have not been verified locally on a development machine;
  watch the logs on their first run.
- The current engine ABI does not export a shared texture handle, so the canvas actually
  uses the fallback painter (`CustomPaint`) rather than the zero-copy `Texture` path.
- The engine address must be an **anonymously downloadable direct link**; private
  repositories are not supported yet.

### License

GNU Affero General Public License v3.0 — see [`LICENSE`](LICENSE).
