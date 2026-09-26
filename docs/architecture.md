# 编辑器架构

```
lib/
├── app.dart / main.dart          应用根：EasyLocalization、主题、ProviderScope、全局错误界面
├── core/
│   ├── engine/                   引擎抽象 + 内置降级实现（不含任何 UI）
│   │   ├── am_engine.dart        抽象接口 AmEngine / AmEngineBackend / 响应解包
│   │   ├── am_types.dart         契约数据类型（能力、事件、校验、节点/混合/插值枚举）
│   │   ├── ffi_am_engine*.dart   FFI 动态库探测（io / stub 条件导出）
│   │   ├── local_am_engine.dart  内置引擎：完整实现 kLocalEngineMethods
│   │   ├── local_document.dart   文档模型 + 全部 doc.command 操作 + 撤销栈
│   │   ├── local_eval.dart       求值：关键形插值、变形器级联、命中测试
│   │   ├── am_scene_provider.dart 降级画家需要的场景接口
│   │   └── engine_bootstrap.dart 启动策略：插件 → FFI → 内置，绝不抛给 UI
│   ├── project/                  `.amproj` 读写（目录模式 ⇄ ZIP+Deflate）
│   ├── state/                    Riverpod 控制器（设置/文档/工程/运行时/UI/引擎）
│   ├── layout/                   停靠布局与宿主（四区域、拖拽换区、尺寸持久化）
│   ├── theme/                    AppTokens / AppTheme（深色优先）
│   ├── i18n/                     语言列表、`context.t()`、格式化工具
│   ├── shortcuts/                快捷键注册表（字符串 ↔ SingleActivator）
│   └── platform/                 文件选择（file_picker 13 封装）
└── features/
    ├── shell/                    外壳：菜单、工具栏、状态栏、面板注册、设置对话框
    ├── canvas/                   画布：交互、降级画家、洋葱皮
    ├── panels/                   17 个功能面板
    ├── project/                  工程动作（新建/打开/保存/校验/导出/导入）
    └── common/                   通用控件
```

## 分层规则

1. `core/` 不依赖 `features/`，也不出现任何业务文案；所有用户可见文本走 i18n key。
2. UI 只通过 `AmEngine.call(method, params)` 访问引擎；**没有**第二个调用入口。
3. 引擎不可用时 `engine_bootstrap` 降级到内置实现并在通知栏给出可读提示，
   界面**不崩溃、不白屏**（A0-4）。
4. 纹理桥可用时画布用 `Texture` widget，否则用 `CustomPaint` 降级画家；
   两条路径互斥。

## 数据流

```
用户操作 → 面板 dispatch('doc.command', ...) → LocalAmEngine/FfiAmEngine
        → 文档修订号 +1 → documentProvider 重载 → 面板/画布重建
播放：Ticker → PlaybackController.advance(dt) → runtime.seek(time)
        → 参数写入 → sceneProvider 重求值 → 画布重绘
```

## 工程格式（`.amproj`）

* 目录模式：`info.json`、`registry.json`、`assets/`、`metadata/`、`spec/`
  （可选 `work/`、`dist/`、`.amprojignore`）。
* 归档模式：ZIP + Deflate，条目限定在 `kAmprojEntryPrefixes` 白名单内；
  解析时拒绝绝对路径与 `..`（`ZIP_SLIP`）。
* JSON：UTF-8 无 BOM、Tab 缩进、`snake_case`、路径统一 `/`、结尾换行。
* 导出产出 `<name>.amproj` + 伴生 `<name>.amproj.sha256`（64 位小写十六进制）。
* 导入先解包再校验，失败**回滚**删除目标目录。

## 测试

`test/` 覆盖：内置引擎契约（命令/撤销/求值/动作/统计）、
`.amproj` 往返（创建→保存→校验→导出→导入）、校验与安全（哈希不符、
非法名称、zip-slip、非空目标、导入回滚）。

```bash
dart format lib test
flutter analyze
flutter test
```
