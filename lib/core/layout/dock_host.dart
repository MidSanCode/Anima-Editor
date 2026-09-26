/// 面板宿主：按 [DockLayout] 组装左/中/右/底四个区域，
/// 支持标签拖拽换区、分隔条调尺寸、区域显隐。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'dock_layout.dart';

/// 面板标题栏 + 内容的标准外壳。
class PanelFrame extends StatelessWidget {
  const PanelFrame({
    super.key,
    required this.titleKey,
    required this.child,
    this.actions = const <Widget>[],
    this.icon,
    this.dense = true,
  });

  final String titleKey;
  final Widget child;
  final List<Widget> actions;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    return Container(
      color: tokens.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: dense ? 30 : 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: tokens.panelHeader,
              border: Border(bottom: BorderSide(color: tokens.divider)),
            ),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: tokens.divider),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    titleKey.tr(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 面板宿主。
class DockHost extends ConsumerWidget {
  const DockHost({super.key, required this.builders, required this.specs});

  final Map<String, WidgetBuilder> builders;
  final List<DockPanelSpec> specs;

  DockPanelSpec? _spec(String id) {
    for (final spec in specs) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dockLayoutProvider);
    if (layout == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = ref.read(dockLayoutProvider.notifier);
    final tokens = AppTheme.of(context);

    final leftVisible = layout.isVisible(DockSlot.left);
    final rightVisible = layout.isVisible(DockSlot.right);
    final bottomVisible = layout.isVisible(DockSlot.bottom);
    final centerIds = layout.slots[DockSlot.center] ?? const <String>[];

    final center = centerIds.isEmpty
        ? const SizedBox.shrink()
        : _SlotView(
            slot: DockSlot.center,
            layout: layout,
            builders: builders,
            specOf: _spec,
          );

    final middle = Column(
      children: <Widget>[
        Expanded(child: center),
        if (bottomVisible) ...<Widget>[
          _Splitter(
            axis: Axis.vertical,
            onDrag: (delta) => controller.setSize(
              DockSlot.bottom,
              (layout.sizes[DockSlot.bottom] ?? 240) - delta,
            ),
          ),
          SizedBox(
            height: layout.sizes[DockSlot.bottom] ?? 240,
            child: _SlotView(
              slot: DockSlot.bottom,
              layout: layout,
              builders: builders,
              specOf: _spec,
            ),
          ),
        ],
      ],
    );

    return Container(
      color: tokens.divider,
      child: Row(
        children: <Widget>[
          if (leftVisible) ...<Widget>[
            SizedBox(
              width: layout.sizes[DockSlot.left] ?? 260,
              child: _SlotView(
                slot: DockSlot.left,
                layout: layout,
                builders: builders,
                specOf: _spec,
              ),
            ),
            _Splitter(
              axis: Axis.horizontal,
              onDrag: (delta) => controller.setSize(
                DockSlot.left,
                (layout.sizes[DockSlot.left] ?? 260) + delta,
              ),
            ),
          ],
          Expanded(child: middle),
          if (rightVisible) ...<Widget>[
            _Splitter(
              axis: Axis.horizontal,
              onDrag: (delta) => controller.setSize(
                DockSlot.right,
                (layout.sizes[DockSlot.right] ?? 300) - delta,
              ),
            ),
            SizedBox(
              width: layout.sizes[DockSlot.right] ?? 300,
              child: _SlotView(
                slot: DockSlot.right,
                layout: layout,
                builders: builders,
                specOf: _spec,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotView extends ConsumerWidget {
  const _SlotView({
    required this.slot,
    required this.layout,
    required this.builders,
    required this.specOf,
  });

  final DockSlot slot;
  final DockLayout layout;
  final Map<String, WidgetBuilder> builders;
  final DockPanelSpec? Function(String id) specOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final ids = layout.slots[slot] ?? const <String>[];
    if (ids.isEmpty) return const SizedBox.shrink();
    final activeId = layout.active[slot] ?? ids.first;

    return Container(
      color: tokens.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (slot != DockSlot.center || ids.length > 1)
            Container(
              height: 30,
              color: tokens.panelHeader,
              child: _SlotTabs(
                slot: slot,
                ids: ids,
                activeId: activeId,
                specOf: specOf,
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: ids.indexOf(activeId).clamp(0, ids.length - 1),
              children: <Widget>[
                for (final id in ids)
                  builders[id]?.call(context) ??
                      Center(
                        child: Text(
                          'panel.missing'.tr(
                            namedArgs: <String, String>{'id': id},
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotTabs extends ConsumerWidget {
  const _SlotTabs({
    required this.slot,
    required this.ids,
    required this.activeId,
    required this.specOf,
  });

  final DockSlot slot;
  final List<String> ids;
  final String activeId;
  final DockPanelSpec? Function(String id) specOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.of(context);
    final controller = ref.read(dockLayoutProvider.notifier);

    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        final target = ids.indexOf(activeId);
        controller.movePanel(
          details.data,
          slot,
          target < 0 ? ids.length : target,
        );
      },
      builder: (context, candidates, rejected) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: candidates.isEmpty
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: ids.length,
            itemBuilder: (context, index) {
              final id = ids[index];
              final spec = specOf(id);
              final selected = id == activeId;
              final tab = Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? tokens.panelBackground : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    if (spec != null) ...<Widget>[
                      Icon(
                        spec.icon,
                        size: 13,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : tokens.divider,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      spec?.titleKey.tr() ?? id,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (spec?.closable ?? true) ...<Widget>[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => controller.hidePanel(id),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: tokens.divider,
                        ),
                      ),
                    ],
                  ],
                ),
              );

              return Draggable<String>(
                data: id,
                feedback: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.panelHeader,
                      border: Border.all(color: tokens.divider),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      spec?.titleKey.tr() ?? id,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: tab),
                child: InkWell(
                  onTap: () => controller.setActive(slot, id),
                  child: tab,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Splitter extends StatefulWidget {
  const _Splitter({required this.axis, required this.onDrag});

  final Axis axis;
  final void Function(double delta) onDrag;

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final horizontal = widget.axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? (details) => widget.onDrag(details.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => widget.onDrag(details.delta.dy),
        onHorizontalDragStart: horizontal
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragEnd: horizontal
            ? (_) => setState(() => _dragging = false)
            : null,
        onVerticalDragStart: horizontal
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragEnd: horizontal
            ? null
            : (_) => setState(() => _dragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: horizontal ? 4 : null,
          height: horizontal ? null : 4,
          color: _hovering || _dragging
              ? Theme.of(context).colorScheme.primary
              : tokens.divider,
        ),
      ),
    );
  }
}
