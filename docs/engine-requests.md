# 引擎对接需求（编辑器 → engine）

本文档记录编辑器/查看器在实现过程中对 `tasks.md` §3 引擎契约的**补充需求**与
**待确认点**。在原生引擎（`engine/`）交付前，编辑器使用内置降级实现
（`lib/core/engine/local_am_engine.dart`）跑通全部流程，因此以下条目的
“当前行为”均已可用，“期望行为”是原生引擎需要保证的语义。

约定：所有调用都走唯一入口 `am_call(engine, method, params_json) -> response_json`，
成功 `{"ok":true,"result":{...}}`，失败 `{"ok":false,"error":{"code","message"}}`。

---

## 1. 必须补齐的方法

| 方法 | 用途 | 当前（内置实现） | 期望 |
| --- | --- | --- | --- |
| `runtime.params` | 读取当前全部参数值 | `{"params":{"<param_id>":0.0}}` | 同左，键为**参数 id** |
| `runtime.seek` | 直接定位到动作时间（拖拽播放头） | `{"time":0.5,"params":{...},"playing":false}` | 同左；不得改变 `playing` 状态 |
| `renderer.pick` | 画布点选 | 入参 `{x,y,space:"screen"\|"world"}`，返回 `{"id":null\|"<node_id>"}` | 明确 `space` 语义（默认 `screen`） |
| `doc.query` `path:"scene"` | 读取**求值后**的几何（降级画家必需） | `{"drawables":[{"id","vertices":[[x,y],...]}]}` | 见第 3 节 |
| `doc.query` `path:"settings"` | 模型设置 | `{"settings":{...}}` | 同左 |
| `project.info` | 工程元信息 + 已注册文件 + spec 列表 | 见实现 | 同左 |

## 2. 语义澄清

1. **参数寻址**：契约里 `runtime.set_param` / `runtime.set_params` 的键是
   参数 **id**（`doc.query path:"parameters"` 返回的键）。编辑器 UI 全部按 id 寻址。
   内置实现额外接受**参数名**作为别名（`_resolveParamId`），建议原生引擎同样容错。
2. **`doc.command` 的返回值**：当前只返回 `{"revision":n}`。`node.create` /
   `node.duplicate` / `param.create` 等会**新建对象**的命令，调用方拿不到新 id，
   只能整表重载。建议返回 `{"revision":n,"created":["<id>"]}`（可选字段，向后兼容）。
3. **`physics.query` / `spec/physics.json`**：内置实现统一使用
   `{"settings":[...]}` 作为外壳键（`doc.query path:"physics"` 亦同），
   `spec/pose.json` 用 `{"pose":[...]}`。原生引擎需保持一致，否则工程往返会丢数据。
4. **`project.export` 拒绝语义**：校验失败必须以 `{"ok":false,"error":{"code":"VALIDATION_FAILED","detail":{"issues":[...]}}}`
   返回，且**不得产出** `.amproj` 与 `.amproj.sha256`。
5. **`project.import` 回滚**：解包后校验失败（或解析失败）必须删除目标目录，
   不允许留下半成品；目标目录非空时返回 `DEST_NOT_EMPTY` 且不做任何修改。
6. **`renderer.view`**：入参 `{pan:[x,y],zoom,flip_x,flip_y,canvas:[w,h]}`，
   返回 `{"view":{...}}`；编辑器在窗口尺寸变化时防抖调用（约 16ms）。
7. **纹理桥**：`am_renderer_texture_info` 返回 `{"texture_id":n,"width":w,"height":h,"format":"rgba8"}`
   时编辑器使用 Flutter `Texture` widget；返回空/失败时回退到降级画家（`AmSceneProvider`）。
   两者**不得同时**渲染，避免重影。

## 3. 画布几何（最重要的缺口）

`Texture` 路径下，几何留在引擎内，编辑器不需要顶点数据。但引擎不可用时，
降级画家必须自己画。为此编辑器引入了**本地**接口 `AmSceneProvider`
（`lib/core/engine/am_scene_provider.dart`），提供：

* `paramValues` / `view` / `background` / `playingMotion` / `isPlaying` / `expression`
* `buildScene({includeHidden, selectedVertices, selectedNode}) -> AmScene`
* `buildSceneWith({params, includeHidden, selectedNode}) -> AmScene`（洋葱皮：用**历史参数值**求值）

`AmScene` 包含：`bounds`、`drawables`（id/name/vertices/uvs/indices/opacity/blend/texture/draw_order/mask/selectedVertexIds）、
`deformers`（id/name/kind/pivot/angle/scale/rows/cols/control_points/visible/locked）。

**请引擎侧确认**：是否把 `doc.query path:"scene"` 扩展为返回上述完整结构
（当前只返回 `drawables[].id/vertices`）。若确认，编辑器可把降级画家统一到契约上，
删掉 `AmSceneProvider` 这一本地扩展。

## 4. 插件与打包

* `pubspec.yaml` 中 `anima_engine` 路径依赖目前**保持注释**：引擎仓库未就绪时
  `flutter pub get` 会直接失败。引擎交付后取消注释即可（编辑器已按
  “插件优先、FFI 次之、内置兜底”的顺序探测，见 `engine_bootstrap.dart`）。
* FFI 动态库探测顺序（`ffi_am_engine.dart`）：环境变量 `ANIMA_ENGINE_LIB`
  → `anima_engine.dll` / `libanima_engine.so` / `libanima_engine.dylib`
  → `am_engine.dll` / `libam_ffi.so`。
* 符号：`am_engine_create` / `am_engine_destroy` / `am_call` / `am_string_free` /
  `am_set_event_callback` / `am_renderer_texture_info` / `am_engine_version`。
* 事件回调（`am_set_event_callback`）负载为 JSON 字符串，类型：
  `frame_presented` / `doc_changed` / `error` / `progress`；编辑器把它们转成
  `AmEvent` 并广播到 `engineEventsProvider`。

## 5. 已修复/已确认的内置实现行为

* `AmprojWriter.writeAsset` 现在会同步重建 `registry.json`，否则校验报 `UNREGISTERED_ASSET`。
* `AmprojWriter.importArchive` 在**任何** `AmException`（含解析失败）时回滚目标目录。
* 关键形求值：同一节点被多个参数驱动时，各参数贡献**叠加**（`base + Σ blendDelta`），
  不再相互覆盖；`AmSceneBuilder` 的 `blendDelta` 已实现。
