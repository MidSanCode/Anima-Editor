/// 菜单栏：文件 / 编辑 / 视图 / 面板 / 帮助，以及帮助类对话框。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/dock_layout.dart';
import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/engine_providers.dart';
import '../../core/state/project_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';
import '../project/project_actions.dart';
import 'panel_registry.dart';
import 'preferences_dialog.dart';

/// 菜单栏。
class EditorMenuBar extends ConsumerWidget {
  const EditorMenuBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final project = ref.watch(projectProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final controller = ref.read(dockLayoutProvider.notifier);

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: tokens.panelHeader,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MenuBar(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(
                  Colors.transparent,
                ),
                elevation: const WidgetStatePropertyAll<double>(0),
                padding: const WidgetStatePropertyAll<EdgeInsets>(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
              children: <Widget>[
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      leadingIcon: const Icon(
                        Icons.note_add_outlined,
                        size: 16,
                      ),
                      onPressed: () => ProjectActions.create(context, ref),
                      child: Text('menu.file.new'.tr()),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.folder_open, size: 16),
                      onPressed: () => ProjectActions.open(context, ref),
                      child: Text('menu.file.open'.tr()),
                    ),
                    SubmenuButton(
                      menuChildren: <Widget>[
                        if (ref.watch(recentProjectsProvider).isEmpty)
                          MenuItemButton(
                            onPressed: null,
                            child: Text('menu.file.noRecent'.tr()),
                          )
                        else
                          for (final path in ref.watch(recentProjectsProvider))
                            MenuItemButton(
                              onPressed: () =>
                                  ProjectActions.openRecent(ref, path),
                              child: Text(
                                path,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      child: Text('menu.file.recent'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.save_outlined, size: 16),
                      onPressed: project.hasProject
                          ? () => ProjectActions.save(ref)
                          : null,
                      child: Text('menu.file.save'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: project.hasProject
                          ? () => ProjectActions.saveAs(context, ref)
                          : null,
                      child: Text('menu.file.saveAs'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.archive_outlined, size: 16),
                      onPressed: project.hasProject
                          ? () => ProjectActions.export(context, ref)
                          : null,
                      child: Text('menu.file.export'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: project.hasProject
                          ? () => ProjectActions.export(
                              context,
                              ref,
                              chooseDirectory: true,
                            )
                          : null,
                      child: Text('menu.file.exportTo'.tr()),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(
                        Icons.unarchive_outlined,
                        size: 16,
                      ),
                      onPressed: () => ProjectActions.import(context, ref),
                      child: Text('menu.file.import'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: project.hasProject
                          ? () => ProjectActions.close(context, ref)
                          : null,
                      child: Text('menu.file.close'.tr()),
                    ),
                  ],
                  child: Text('menu.file'.tr()),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.undo, size: 16),
                      onPressed: document.canUndo
                          ? () => ref.read(documentProvider.notifier).undo()
                          : null,
                      child: Text('menu.edit.undo'.tr()),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.redo, size: 16),
                      onPressed: document.canRedo
                          ? () => ref.read(documentProvider.notifier).redo()
                          : null,
                      child: Text('menu.edit.redo'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: () {
                        final selection = ref.read(selectionProvider);
                        if (selection.primary == null) return;
                        ref.read(documentProvider.notifier).dispatch(
                          'node.duplicate',
                          <String, Object?>{'id': selection.primary},
                        );
                      },
                      child: Text('menu.edit.duplicate'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () {
                        final selection = ref.read(selectionProvider);
                        if (selection.primary == null) return;
                        ref.read(documentProvider.notifier).dispatch(
                          'node.delete',
                          <String, Object?>{'id': selection.primary},
                        );
                        ref.read(selectionProvider.notifier).clear();
                      },
                      child: Text('menu.edit.delete'.tr()),
                    ),
                  ],
                  child: Text('menu.edit'.tr()),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.fit_screen, size: 16),
                      onPressed: () =>
                          ref.read(viewportProvider.notifier).requestFit(),
                      child: Text('menu.view.fit'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () =>
                          ref.read(viewportProvider.notifier).reset(),
                      child: Text('menu.view.reset'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .patch((s) => s.copyWith(showGrid: !s.showGrid)),
                      child: Text('menu.view.toggleGrid'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .patch((s) => s.copyWith(showGuides: !s.showGuides)),
                      child: Text('menu.view.toggleGuides'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .patch((s) => s.copyWith(onionSkin: !s.onionSkin)),
                      child: Text('menu.view.toggleOnion'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: controller.reset,
                      child: Text('menu.view.resetLayout'.tr()),
                    ),
                  ],
                  child: Text('menu.view'.tr()),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    for (final spec in kEditorPanelSpecs)
                      MenuItemButton(
                        leadingIcon: Icon(spec.icon, size: 16),
                        onPressed: () => controller.togglePanel(spec.id),
                        child: Text(spec.titleKey.tr()),
                      ),
                    const Divider(height: 1),
                    for (final slot in <DockSlot>[
                      DockSlot.left,
                      DockSlot.right,
                      DockSlot.bottom,
                    ])
                      MenuItemButton(
                        onPressed: () => controller.toggleSlot(slot),
                        child: Text('menu.panel.${slot.wire}'.tr()),
                      ),
                  ],
                  child: Text('menu.panel'.tr()),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      onPressed: () => showShortcutHelp(context, settings),
                      child: Text('menu.help.shortcuts'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () => showEngineDiagnostics(context, ref),
                      child: Text('menu.help.engine'.tr()),
                    ),
                    MenuItemButton(
                      onPressed: () => showPreferences(context, ref),
                      child: Text('menu.help.preferences'.tr()),
                    ),
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: () => showAbout(context),
                      child: Text('menu.help.about'.tr()),
                    ),
                  ],
                  child: Text('menu.help'.tr()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              project.displayName ?? project.name ?? 'app.title'.tr(),
              style: TextStyle(fontSize: 11, color: tokens.divider),
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷键帮助。
Future<void> showShortcutHelp(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('dialog.shortcuts'.tr()),
      content: SizedBox(
        width: 380,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final entry in shortcutActionKeys.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.value.tr(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      AmShortcuts.label(settings.shortcuts[entry.key] ?? ''),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.close'.tr()),
        ),
      ],
    ),
  );
}

/// 引擎诊断。
Future<void> showEngineDiagnostics(BuildContext context, WidgetRef ref) {
  final boot = ref.read(engineStatusProvider);
  final capabilities = ref.read(engineCapabilitiesProvider);
  final texture = ref.read(engineTextureProvider);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('dialog.engine'.tr()),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KeyValueRow(
                labelKey: 'dialog.engine.backend',
                value: boot.backend.id,
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.label',
                value: boot.backend.label.tr(),
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.detail',
                value: boot.backend.detail,
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.engine',
                value: capabilities.engine,
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.sdk',
                value: capabilities.sdk,
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.format',
                value: capabilities.format,
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.texture',
                value: texture == null
                    ? '—'
                    : '${texture.width}x${texture.height} #${texture.textureId}',
              ),
              KeyValueRow(
                labelKey: 'dialog.engine.methods',
                value: '${capabilities.methods.length}',
              ),
              if (boot.warningKey != null)
                KeyValueRow(
                  labelKey: 'dialog.engine.warning',
                  value: boot.warningKey!.tr(),
                ),
              for (final entry in boot.notes.entries)
                KeyValueRow(
                  labelKey: 'dialog.engine.note',
                  value: '${entry.key}: ${entry.value}',
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.close'.tr()),
        ),
      ],
    ),
  );
}

/// 关于。
Future<void> showAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('app.title'.tr()),
    content: const AboutCard(),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('common.close'.tr()),
      ),
    ],
  ),
);
