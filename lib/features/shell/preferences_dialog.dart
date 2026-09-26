/// 设置对话框：语言、主题、引擎、自动保存、渲染质量、快捷键（AE5-1）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/l10n.dart';
import '../../core/shortcuts/shortcut_registry.dart';
import '../../core/state/settings_controller.dart';
import '../common/widgets.dart';

/// 打开设置。
Future<void> showPreferences(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _PreferencesDialog(),
  );
}

class _PreferencesDialog extends ConsumerStatefulWidget {
  const _PreferencesDialog();

  @override
  ConsumerState<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends ConsumerState<_PreferencesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final controller = ref.read(settingsProvider.notifier);

    return AlertDialog(
      title: Text('dialog.preferences'.tr()),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: <Widget>[
            TabBar(
              controller: _tabs,
              tabs: <Widget>[
                Tab(text: 'settings.tab.general'.tr()),
                Tab(text: 'settings.tab.engine'.tr()),
                Tab(text: 'settings.tab.shortcuts'.tr()),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: <Widget>[
                  _general(settings, controller),
                  _engine(settings, controller),
                  _shortcuts(settings, controller),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            final ok = await confirmDialog(
              context,
              titleKey: 'settings.resetTitle',
              messageKey: 'settings.resetMessage',
            );
            if (!ok) return;
            await controller.patch((_) => const AppSettings());
            if (!context.mounted) return;
            await context.setLocale(
              L10n.resolve(
                kLocaleSystem,
                WidgetsBinding.instance.platformDispatcher.locale,
              ),
            );
          },
          child: Text('settings.reset'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }

  Widget _general(AppSettings settings, SettingsController controller) {
    return ListView(
      children: <Widget>[
        SectionHeader(titleKey: 'settings.section.language'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: EnumDropdown<String>(
            value: settings.localeCode,
            items: <String>[
              kLocaleSystem,
              for (final locale in L10n.supportedLocales) L10n.codeOf(locale),
            ],
            labelOf: (code) => code == kLocaleSystem
                ? 'settings.language.system'.tr()
                : L10n.displayName(L10n.resolve(code, const Locale('en'))),
            onChanged: (code) async {
              if (code == null) return;
              await controller.patch((s) => s.copyWith(localeCode: code));
              if (!mounted) return;
              await context.setLocale(
                L10n.resolve(
                  code,
                  WidgetsBinding.instance.platformDispatcher.locale,
                ),
              );
            },
          ),
        ),
        SectionHeader(titleKey: 'settings.section.theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: EnumDropdown<ThemeMode>(
            value: settings.themeMode,
            items: ThemeMode.values,
            labelOf: (mode) => 'settings.theme.${mode.name}'.tr(),
            onChanged: (mode) {
              if (mode == null) return;
              controller.patch((s) => s.copyWith(themeMode: mode));
            },
          ),
        ),
        SectionHeader(titleKey: 'settings.section.autosave'),
        LabeledSlider(
          label: 'settings.autosaveInterval'.tr(),
          value: settings.autosaveSeconds.toDouble(),
          min: 0,
          max: 900,
          digits: 0,
          suffix: settings.autosaveSeconds == 0
              ? 'settings.autosaveOff'.tr()
              : null,
          onChanged: (value) => controller.patch(
            (s) => s.copyWith(autosaveSeconds: value.round()),
          ),
        ),
      ],
    );
  }

  Widget _engine(AppSettings settings, SettingsController controller) {
    return ListView(
      children: <Widget>[
        SectionHeader(titleKey: 'settings.section.engine'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: EnumDropdown<String>(
            value: settings.engineMode,
            items: const <String>['auto', 'local'],
            labelOf: (mode) => 'settings.engine.$mode'.tr(),
            onChanged: (mode) {
              if (mode == null) return;
              controller.patch((s) => s.copyWith(engineMode: mode));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'settings.engine.hint'.tr(),
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
        SectionHeader(titleKey: 'settings.section.render'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: EnumDropdown<String>(
            value: settings.renderQuality,
            items: const <String>['low', 'medium', 'high'],
            labelOf: (value) => 'settings.quality.$value'.tr(),
            onChanged: (value) {
              if (value == null) return;
              controller.patch((s) => s.copyWith(renderQuality: value));
            },
          ),
        ),
        LabeledSlider(
          label: 'settings.devicePixelRatio'.tr(),
          value: settings.devicePixelRatioOverride,
          min: 0.5,
          max: 4,
          defaultValue: 1,
          onChanged: (value) => controller.patch(
            (s) => s.copyWith(devicePixelRatioOverride: value),
          ),
        ),
        SwitchRow(
          labelKey: 'settings.showGrid',
          value: settings.showGrid,
          onChanged: (value) =>
              controller.patch((s) => s.copyWith(showGrid: value)),
        ),
        SwitchRow(
          labelKey: 'settings.showGuides',
          value: settings.showGuides,
          onChanged: (value) =>
              controller.patch((s) => s.copyWith(showGuides: value)),
        ),
        SwitchRow(
          labelKey: 'settings.onionSkin',
          value: settings.onionSkin,
          onChanged: (value) =>
              controller.patch((s) => s.copyWith(onionSkin: value)),
        ),
        LabeledSlider(
          label: 'settings.onionSkinFrames'.tr(),
          value: settings.onionSkinFrames.toDouble(),
          min: 1,
          max: 6,
          digits: 0,
          onChanged: (value) => controller.patch(
            (s) => s.copyWith(onionSkinFrames: value.round()),
          ),
        ),
      ],
    );
  }

  Widget _shortcuts(AppSettings settings, SettingsController controller) {
    return ListView(
      children: <Widget>[
        for (final entry in shortcutActionKeys.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.value.tr(),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: _BindingField(
                    value: settings.shortcuts[entry.key] ?? '',
                    onSubmit: (value) => controller.patch(
                      (s) => s.copyWith(
                        shortcuts: <String, String>{
                          ...s.shortcuts,
                          entry.key: value,
                        },
                      ),
                    ),
                  ),
                ),
                SmallIconButton(
                  icon: Icons.restart_alt,
                  tooltipKey: 'settings.shortcutReset',
                  onPressed: () => controller.patch(
                    (s) => s.copyWith(
                      shortcuts: <String, String>{
                        ...s.shortcuts,
                        entry.key:
                            AppSettings.defaultShortcuts[entry.key] ?? '',
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BindingField extends StatefulWidget {
  const _BindingField({required this.value, required this.onSubmit});

  final String value;
  final ValueChanged<String> onSubmit;

  @override
  State<_BindingField> createState() => _BindingFieldState();
}

class _BindingFieldState extends State<_BindingField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    style: const TextStyle(fontSize: 11.5),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    onSubmitted: (value) {
      if (AmShortcuts.parse(value) == null) return;
      widget.onSubmit(value.trim().toLowerCase());
    },
  );
}
