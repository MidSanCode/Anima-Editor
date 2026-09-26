/// 起始页：新建 / 打开 / 最近工程 / 示例（AE5-2）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/project_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';
import '../project/project_actions.dart';

/// 起始页。
class StartPage extends ConsumerWidget {
  const StartPage({super.key, required this.onContinue});

  /// 跳过工程直接进入编辑器（示例 / 空文档）。
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final recent = ref.watch(recentProjectsProvider);
    final project = ref.watch(projectProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.animation,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'app.title'.tr(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'app.description'.tr(),
                        style: TextStyle(fontSize: 11.5, color: tokens.divider),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SectionHeader(titleKey: 'start.section.actions'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _ActionCard(
                    icon: Icons.note_add_outlined,
                    titleKey: 'start.newProject',
                    subtitleKey: 'start.newProjectHint',
                    onTap: () => ProjectActions.create(context, ref),
                  ),
                  _ActionCard(
                    icon: Icons.folder_open,
                    titleKey: 'start.openProject',
                    subtitleKey: 'start.openProjectHint',
                    onTap: () => ProjectActions.open(context, ref),
                  ),
                  _ActionCard(
                    icon: Icons.unarchive_outlined,
                    titleKey: 'start.importProject',
                    subtitleKey: 'start.importProjectHint',
                    onTap: () => ProjectActions.import(context, ref),
                  ),
                  _ActionCard(
                    icon: Icons.auto_awesome,
                    titleKey: 'start.sample',
                    subtitleKey: 'start.sampleHint',
                    onTap: onContinue,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionHeader(
                titleKey: 'start.section.recent',
                actions: <Widget>[
                  if (recent.isNotEmpty)
                    SmallTextButton(
                      labelKey: 'start.clearRecent',
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .patch((s) => s.copyWith(recentProjects: <String>[])),
                    ),
                ],
              ),
              if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Text(
                    'start.noRecent'.tr(),
                    style: TextStyle(fontSize: 11.5, color: tokens.divider),
                  ),
                )
              else
                for (final path in recent)
                  ListRow(
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SmallIconButton(
                          icon: Icons.open_in_new,
                          tooltipKey: 'start.open',
                          onPressed: () => ProjectActions.openRecent(ref, path),
                        ),
                        SmallIconButton(
                          icon: Icons.close,
                          tooltipKey: 'start.forget',
                          onPressed: () =>
                              ProjectActions.forgetRecent(ref, path),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _basename(path),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        Text(
                          path,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: tokens.divider),
                        ),
                      ],
                    ),
                  ),
              if (project.busy) ...<Widget>[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 24),
              Text(
                'start.hint'.tr(),
                style: TextStyle(fontSize: 10.5, color: tokens.divider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.onTap,
  });

  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    return SizedBox(
      width: 166,
      height: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.panelHeader,
            borderRadius: BorderRadius.circular(tokens.panelRadius),
            border: Border.all(color: tokens.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20),
              const Spacer(),
              Text(
                titleKey.tr(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitleKey.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: tokens.divider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
