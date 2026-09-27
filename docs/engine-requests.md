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

* **编辑命令不进引擎。** 引擎 `doc.command` 的 `op` 是**下划线**形式，且只覆盖
  模型结构（`node_create` / `mesh_set` / `keyform_record` / `parameter_add`…）；
  物理、动作、表情、姿势、设置**没有编辑命令**。UI 用的是点号 op
  （`physics.add_setting` / `expression.create` / `settings.set`…），直接透传只会
  得到 `命令无法解析`。做法：`ContractAmEngine` 内挂一份**影子文档**
  （`LocalDocument`，已实现全部 55 个宿主 op + 撤销重做 + 绘制顺序），
  `doc.command` 先在影子上生效，再经 `engine_spec_codec.dart` 投影成引擎 `Spec`，
  用 `project.set_spec` 一次性推给引擎求值。
* **撤销重做由影子文档负责。** `project.set_spec` 会重建引擎的 `Document`
  （撤销栈、时钟、动作播放、表情归零；参数值由 `ParamStore::sync_with_model`
  保留），所以 `doc.undo`/`doc.redo`/`doc.history` 一律读影子文档。
* **宿主扩展通道。** 引擎 `Spec` 表达不了宿主的部分字段（`bounds`、
  `warp.control_points` 的宿主形状、`pendulum.{length,frequency,damping}`、
  `keys[].in_tangent/out_tangent`、`art_path` 等）。整份宿主文档挂在
  `spec/config.json` 的 `__host.doc` 上 —— `ProjectConfig` 是
  `#[serde(flatten)]`，未知键原样往返，`project.save`/`project.load` 都不丢。
  读回时优先用 `__host.doc`；没有（老工程/引擎原生工程）则按引擎形状重建。
* `project.load` 结果**不含 `name`** → 从 `project.spec` 的 `model.name` 或
  `info.json` 取。
* `project.create` 引擎没有 → 宿主先写 `info.json`/`registry.json`/`spec/`
  （`project.save` 在目录已存在时走 `Project::open`，要求这两个文件），
  影子文档重置为默认空工程，再 `project.set_spec` + `project.save` 落盘。
  `project.save` / `project.load` 都**不回传 `display_name`**，
  所以适配层自己记住刚写下的 `info.json` 值。
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
| 4 | 动作/物理/表情的**编辑**能力 | 引擎只有运行时播放与 `spec` 层替换；编辑器改用影子文档 + `project.set_spec` 绕过（见 §2） | 补齐动作关键帧增删改、物理设置读写、表情增删改的编辑操作，编辑器即可去掉影子文档的整份推送 |
| 5 | 暴露 `project.create` | `am-format` 有 `Project::create`，但 `am_call` 没暴露；宿主只能自己写 `info.json` + `project.save` 绕 | 直接暴露建目录 + 空 spec 的方法，宿主就不必自己写 `info.json` |
| 6 | `diagnostics.stats` 字段稳定性 | 字段：`nodes/parameters/textures/motions/expressions/physics/drawables/revision/dirty/frame` | 性能面板按 `stat.<field>` 取文案，请保持字段名稳定或提前通知 |
| 7 | `project.load` / `project.save` 回传 `name` + `display_name` | 只有 `path/nodes/parameters/motions/expressions` | 回传 `model.name` 与 `info.display_name`，省掉宿主自己记名字 |
| 8 | `project.save {path}` 对已存在目录的语义 | 目录存在 → `Project::open`（要求 `info.json`，否则报错）；不存在 → `Project::create` | 建议目录存在但为空时也走 `Project::create`，或明确报「目录非空/不是工程」 |
| 9 | `doc.command` 的 `op` 大小写/分隔符与 UI 不一致 | 引擎用下划线（`node_create`），UI 用点号（`node.create`） | 建议接受点号别名（或提供 op 列表查询），宿主就不必维护映射 |

已确认的语义：

* `min_sdk` 是**格式版本整数**（`format.schema.json`：`integer, minimum 1`），不是 semver 字符串。
* `spec/model.json` 的 `nodes` 是**数组**（字段 `kind`），不是以 id 为键的映射。
* `project.save {path}`：path 是目录 → 打开并写入；否则按 `Project::create` 处理。
* `project.new {name, width?, height?}`：只改内存模型，不落盘；画布默认 1024×1024。

## 4. 降级与打包

* `pubspec.yaml` 中的 `anima_engine` 路径依赖**保持注释**：真实接入走 C ABI，
  不依赖 Flutter 插件；引擎未就绪时 `flutter pub get` 也不会失败。
* 启动策略（`engine_bootstrap.dart`）：FFI → 内置实现。
  FFI 成功时用 `ContractAmEngine` 包装，`warningKey` 为 `null`；
  降级时 `warningKey = 'engine.warning.fallback'`，界面显示横幅而非崩溃。
