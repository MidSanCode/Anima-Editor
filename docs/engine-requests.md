# 引擎对接需求（编辑器 → engine）

> 状态：**原生引擎已交付并接通**。编辑器通过 `anima.dll` 的 C ABI 直接驱动真实引擎；
> `lib/core/engine/local_am_engine.dart`（内置实现）保留为**降级路径**，
> 引擎缺失/初始化失败时自动接管，保证 A0-5「绝不崩溃或白屏」。

本文档记录接入后的**实际契约**、编辑器侧的**翻译层**，以及仍需引擎侧补齐的条目。

---

## 1. 实际使用的 C ABI

来源：`engine/crates/am-ffi/bindings/include/anima.h`。

| 符号 | 用途 |
| --- | --- |
| `const char* am_version(void)` | 引擎版本（静态字符串，不需释放） |
| `am_engine* am_engine_new(void)` | 建空引擎 |
| `am_engine* am_engine_new_from_file(const char* path)` | 从工程建引擎 |
| `void am_engine_free(am_engine*)` | 释放 |
| `char* am_call(am_engine*, const char* method, const char* params_json)` | 唯一方法入口，返回 JSON（**需 `am_string_free`**） |
| `void am_string_free(char*)` | 释放 `am_call` 返回值 |
| `size_t am_frame_copy(am_engine*, uint8_t* out, size_t capacity)` | 回读离屏帧像素 |
| `void am_set_event_callback(am_engine*, am_event_cb, void* user_data)` | 事件订阅 |
| `const char* am_last_error(void)` | 最近错误（静态字符串） |

约定：

* 信封 `{"ok":true,"result":{...}}` / `{"ok":false,"error":{"code":<int>,"message":"..."}}`；
  错误码是**数字**（`-32600`/`-32601`/`-32602`/`-32603`/`-32000`）。
* `am_engine*` **非线程安全、不可重入**；编辑器所有调用串行化。
* 动态库探测顺序（`lib/core/engine/ffi_am_engine_io.dart`）：
  环境变量 `ANIMA_ENGINE_LIB` → `anima.dll`（Windows）/ `libanima.dylib` / `libanima.so`；
  搜索根依次为 `''`、当前目录、可执行文件目录、`exeDir/data`、`exeDir/lib`、
  `../engine/target/debug`、`../engine/target/release`，最后回退 `DynamicLibrary.process()`。
  全部失败 → `tryCreateFfiEngine` 返回 `null`，上层降级，**不抛异常**。

## 2. 引擎方法面 vs UI 方法面

引擎真实方法（`am-core` 派发）：`system.ping/version/capabilities`；
`project.new/load/save/validate/spec/set_spec`；`doc.command/undo/redo/history/model/set_model/evaluate`；
`runtime.set_param/params/reset_params/advance/set_time/pause/resume/state/scene`；
`motion.list/play/stop/pause/resume/seek/state`；`expression.list/set`；
`physics.info/step/reset`；`renderer.info/init/resize/set_view/set_texture/clear_textures/render/frame/save_png`；
`diagnostics.stats`。

UI 期望的方法面不同（`project.create/close/info/export/import/set_config`；
`doc.query/revision`；`runtime.step/seek/play_motion/...`；`renderer.create/destroy/frame/pick/measure` 等）。
**做法：UI 方法面保持不变，全部在 `lib/core/engine/contract_am_engine.dart`
（`ContractAmEngine`）里翻译**，因此面板代码不感知引擎细节。

翻译层要点：

* `project.load` 结果**不含 `name`** → 从 `project.spec` 的 `model.name` 取。
* `doc.undo` / `doc.redo` 会改变结构 → 必须重新拉 `project.spec` 刷新缓存，
  否则 `doc.query path:"hierarchy"` 返回旧节点表。
* 眨眼/呼吸/口型（`runtime.blink/breath/lipsync`）引擎没有 → **宿主侧**实现，
  按参数名（`EyeOpen` / `Breath` / `MouthOpen`）写 `runtime.set_param`。
* `.amproj` 压缩包导出/导入引擎没有 → 宿主侧 `AmprojWriter`；适配层对这些方法抛
  `AmException('UNSUPPORTED')`，由 UI 走宿主路径。
* `renderer.*` 只维护视图状态；实际显示当前走降级画家（见第 3 节）。

## 3. 仍需引擎侧补齐（按优先级）

| # | 条目 | 现状 | 期望 |
| --- | --- | --- | --- |
| 1 | **外部纹理桥** | ABI 无纹理句柄导出；画布只能用降级画家（`AmSceneProvider`）重绘 | 暴露离屏帧的共享纹理句柄（或确认 `renderer.render` + `am_frame_copy` + `decodeImageFromPixels` 为受支持路径），使画布走 `Texture` widget |
| 2 | `doc.query path:"scene"` 完整性 | 仅 `drawables[].id/vertices` | 返回完整几何（`uvs`/`indices`/`opacity`/`blend`/`texture`/`draw_order`/`mask`）与 `deformers`，编辑器即可删掉本地 `AmSceneProvider` |
| 3 | `doc.command` 新建对象返回 id | 只返回 `{effects, revision}` | 追加可选 `created:["<id>"]`（向后兼容），免去整表重载 |
| 4 | 动作/物理/表情的**编辑**能力 | 引擎只有运行时播放与 `spec` 层替换 | 补齐动作关键帧增删改、物理设置读写、表情增删改的编辑操作 |
| 5 | `project.create` 脚手架 | 宿主侧写目录 | 若引擎愿意接管，暴露建目录+空 spec 的方法 |
| 6 | `diagnostics.stats` 字段稳定性 | 字段：`nodes/parameters/textures/motions/expressions/physics/drawables/revision/dirty/frame` | 性能面板按 `stat.<field>` 取文案，请保持字段名稳定或提前通知 |
| 7 | `project.load` 回传 `name` | 无 | 建议直接回传 `model.name`，省一次 `project.spec` |

已确认的语义：

* `min_sdk` 是**格式版本整数**（`format.schema.json`：`integer, minimum 1`），不是 semver 字符串。
* `spec/model.json` 的 `nodes` 是**数组**（字段 `kind`），不是以 id 为键的映射。
* `project.save {path}`：path 是目录 → 打开并写入；否则按 `Project::create` 处理。

## 4. 降级与打包

* `pubspec.yaml` 中的 `anima_engine` 路径依赖**保持注释**：真实接入走 C ABI，
  不依赖 Flutter 插件；引擎未就绪时 `flutter pub get` 也不会失败。
* 启动策略（`engine_bootstrap.dart`）：FFI → 内置实现。
  FFI 成功时用 `ContractAmEngine` 包装，`warningKey` 为 `null`；
  降级时 `warningKey = 'engine.warning.fallback'`，界面显示横幅而非崩溃。
