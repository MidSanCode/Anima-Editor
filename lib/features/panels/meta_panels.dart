/// 元信息类面板：校验、历史、性能（AE1-4 / AE5-5）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/engine_providers.dart';
import '../../core/state/project_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 校验面板。
class ValidationPanel extends ConsumerWidget {
  const ValidationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final project = ref.watch(projectProvider);
    final report = project.report;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              SmallTextButton(
                labelKey: 'panel.validation.run',
                icon: Icons.rule,
                onPressed: project.busy
                    ? null
                    : () => ref.read(projectProvider.notifier).validate(),
              ),
              const Spacer(),
              if (report != null)
                Text(
                  report.ok
                      ? 'panel.validation.passed'.tr()
                      : 'panel.validation.failed'.tr(
                          namedArgs: <String, String>{
                            'count': '${report.errorCount}',
                          },
                        ),
                  style: TextStyle(
                    fontSize: 11,
                    color: report.ok ? tokens.accentSecondary : tokens.danger,
                  ),
                ),
            ],
          ),
        ),
        if (project.exportPath != null)
          KeyValueRow(
            labelKey: 'panel.validation.lastExport',
            value: project.exportPath!,
            monospace: true,
          ),
        if (project.exportSha256 != null)
          KeyValueRow(
            labelKey: 'panel.validation.sha256',
            value: project.exportSha256!,
            monospace: true,
          ),
        Expanded(
          child: report == null
              ? EmptyState(
                  icon: Icons.verified_outlined,
                  titleKey: 'panel.validation.empty',
                  subtitleKey: 'panel.validation.emptyHint',
                )
              : report.issues.isEmpty
              ? EmptyState(
                  icon: Icons.check_circle_outline,
                  titleKey: 'panel.validation.passed',
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final issue in report.issues) _IssueRow(issue: issue),
                  ],
                ),
        ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

  final AmValidationIssue issue;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final color = switch (issue.severity) {
      'error' => tokens.danger,
      'warning' => tokens.warning,
      _ => tokens.divider,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            issue.isError ? Icons.error_outline : Icons.warning_amber,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  issue.code,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (issue.path.isNotEmpty)
                  Text(
                    issue.path,
                    style: TextStyle(fontSize: 10, color: tokens.divider),
                  ),
                if (issue.message.isNotEmpty)
                  Text(issue.message, style: const TextStyle(fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 历史面板。
class HistoryPanel extends ConsumerWidget {
  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final controller = ref.read(documentProvider.notifier);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: <Widget>[
              SmallIconButton(
                icon: Icons.undo,
                tooltipKey: 'edit.undo',
                onPressed: document.canUndo ? controller.undo : null,
              ),
              SmallIconButton(
                icon: Icons.redo,
                tooltipKey: 'edit.redo',
                onPressed: document.canRedo ? controller.redo : null,
              ),
              const Spacer(),
              Text(
                '${document.history.length}',
                style: TextStyle(fontSize: 10.5, color: tokens.divider),
              ),
            ],
          ),
        ),
        Expanded(
          child: document.history.isEmpty
              ? EmptyState(
                  icon: Icons.history,
                  titleKey: 'panel.history.empty',
                  subtitleKey: 'panel.history.emptyHint',
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  reverse: true,
                  itemCount: document.history.length,
                  itemBuilder: (context, index) {
                    final entry =
                        document.history[document.history.length - 1 - index];
                    return ListRow(
                      trailing: Text(
                        '#${document.history.length - index}',
                        style: TextStyle(fontSize: 10, color: tokens.divider),
                      ),
                      child: Text(entry, style: const TextStyle(fontSize: 11)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 性能面板。
class PerformancePanel extends ConsumerWidget {
  const PerformancePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final stats = ref.watch(statsProvider);
    final status = ref.watch(engineStatusProvider);
    final capabilities = ref.watch(engineCapabilitiesProvider);
    final texture = ref.watch(engineTextureProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    return PanelScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(titleKey: 'panel.performance.section.engine'),
          KeyValueRow(
            labelKey: 'panel.performance.backend',
            value: '${status.backend.id} · ${status.backend.label.tr()}',
          ),
          KeyValueRow(
            labelKey: 'panel.performance.engineVersion',
            value: capabilities.engine,
          ),
          KeyValueRow(
            labelKey: 'panel.performance.sdk',
            value: capabilities.sdk,
          ),
          KeyValueRow(
            labelKey: 'panel.performance.texture',
            value: texture == null
                ? '—'
                : '${texture.width}x${texture.height} · ${texture.format}',
          ),
          KeyValueRow(
            labelKey: 'panel.performance.bridged',
            value: '${texture?.isBridged ?? false}',
          ),
          SectionHeader(titleKey: 'panel.performance.section.stats'),
          stats.when(
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final entry in data.entries)
                  KeyValueRow(
                    labelKey: 'stat.${entry.key}',
                    value: '${entry.value}',
                  ),
              ],
            ),
            loading: () => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'common.loading'.tr(),
                style: TextStyle(fontSize: 11, color: tokens.divider),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '$error',
                style: TextStyle(fontSize: 11, color: tokens.danger),
              ),
            ),
          ),
          SectionHeader(titleKey: 'panel.performance.section.capabilities'),
          for (final capability in capabilities.methods)
            KeyValueRow(labelKey: capability, value: '✓'),
          SectionHeader(titleKey: 'panel.performance.section.settings'),
          KeyValueRow(
            labelKey: 'settings.renderQuality',
            value: settings.renderQuality,
          ),
          KeyValueRow(
            labelKey: 'settings.devicePixelRatio',
            value: settings.devicePixelRatioOverride.toStringAsFixed(2),
          ),
        ],
      ),
    );
  }
}
