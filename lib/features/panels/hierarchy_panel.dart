/// 层级面板：部件树、绘制顺序、可见性/锁定、重命名、拖拽父子、删除（AE1-1）。
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/am_types.dart';
import '../../core/state/document_controller.dart';
import '../../core/state/ui_controllers.dart';
import '../../core/theme/app_theme.dart';
import '../common/widgets.dart';

/// 层级 / 绘制顺序视图。
class HierarchyPanel extends ConsumerStatefulWidget {
  const HierarchyPanel({super.key});

  @override
  ConsumerState<HierarchyPanel> createState() => _HierarchyPanelState();
}

class _HierarchyPanelState extends ConsumerState<HierarchyPanel> {
  final Set<String> _collapsed = <String>{};
  final TextEditingController _filter = TextEditingController();
  String _query = '';
  bool _drawOrder = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.of(context);
    final document = ref.watch(documentProvider);
    final selection = ref.watch(selectionProvider);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _filter,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'panel.hierarchy.search'.tr(),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              SmallIconButton(
                icon: Icons.account_tree,
                tooltipKey: 'panel.hierarchy.viewTree',
                selected: !_drawOrder,
                onPressed: () => setState(() => _drawOrder = false),
              ),
              SmallIconButton(
                icon: Icons.format_list_numbered,
                tooltipKey: 'panel.hierarchy.viewDrawOrder',
                selected: _drawOrder,
                onPressed: () => setState(() => _drawOrder = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: document.loaded == false && document.rootId == null
              ? EmptyState(
                  icon: Icons.account_tree_outlined,
                  titleKey: 'panel.hierarchy.empty',
                  subtitleKey: 'panel.hierarchy.emptyHint',
                )
              : _drawOrder
              ? _buildDrawOrder(document, selection)
              : _buildTree(document, selection, tokens),
        ),
        _buildFooter(document, selection),
      ],
    );
  }

  Widget _buildTree(
    DocumentState document,
    SelectionState selection,
    AppTokens tokens,
  ) {
    final root = document.rootId;
    if (root == null) {
      return EmptyState(
        icon: Icons.account_tree_outlined,
        titleKey: 'panel.hierarchy.empty',
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: _buildBranch(document, selection, root, 0),
    );
  }

  List<Widget> _buildBranch(
    DocumentState document,
    SelectionState selection,
    String id,
    int depth,
  ) {
    final node = document.nodes[id];
    if (node == null) return const <Widget>[];
    final tokens = AppTheme.of(context);
    final name = '${node['name'] ?? id}';
    if (_query.isNotEmpty &&
        !name.toLowerCase().contains(_query.toLowerCase())) {
      // 过滤时仍然递归子节点，保持层级可见。
      final children = document.childrenOf(id);
      final matched = <Widget>[];
      for (final child in children) {
        matched.addAll(_buildBranch(document, selection, child, depth));
      }
      return matched;
    }

    final children = document.childrenOf(id);
    final isCollapsed = _collapsed.contains(id);
    final visible = asBool(node['visible'], true);
    final locked = asBool(node['locked'], false);
    final kind = '${node['kind'] ?? 'part'}';
    final rows = <Widget>[
      DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != id,
        onAcceptWithDetails: (details) => _reparent(details.data, id),
        builder: (context, candidate, rejected) => ListRow(
          key: ValueKey<String>('node-$id'),
          depth: depth,
          selected: selection.nodes.contains(id),
          onTap: () => ref
              .read(selectionProvider.notifier)
              .select(id, additive: HardwareKeyboard.instance.isShiftPressed),
          onSecondaryTap: () => _contextMenu(id),
          leading: SizedBox(
            width: 14,
            child: children.isEmpty
                ? const SizedBox.shrink()
                : InkWell(
                    onTap: () => setState(() {
                      if (isCollapsed) {
                        _collapsed.remove(id);
                      } else {
                        _collapsed.add(id);
                      }
                    }),
                    child: Icon(
                      isCollapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 14,
                    ),
                  ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SmallIconButton(
                icon: visible ? Icons.visibility : Icons.visibility_off,
                tooltipKey: 'panel.hierarchy.toggleVisible',
                onPressed: () => ref.read(documentProvider.notifier).dispatch(
                  'node.set_visible',
                  <String, Object?>{'id': id, 'value': !visible},
                ),
              ),
              SmallIconButton(
                icon: locked ? Icons.lock : Icons.lock_open,
                tooltipKey: 'panel.hierarchy.toggleLocked',
                onPressed: () => ref.read(documentProvider.notifier).dispatch(
                  'node.set_locked',
                  <String, Object?>{'id': id, 'value': !locked},
                ),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(_iconFor(kind), size: 13, color: _colorFor(kind, tokens)),
              const SizedBox(width: 5),
              Expanded(
                child: _InlineName(
                  id: id,
                  name: name,
                  onRename: (value) =>
                      ref.read(documentProvider.notifier).dispatch(
                        'node.rename',
                        <String, Object?>{'id': id, 'name': value},
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    if (!isCollapsed && _query.isEmpty) {
      for (final child in children) {
        rows.addAll(_buildBranch(document, selection, child, depth + 1));
      }
    }
    return rows;
  }

  Widget _buildDrawOrder(DocumentState document, SelectionState selection) {
    final path = document.artPath.isEmpty
        ? document.flatten()
        : document.artPath;
    if (path.isEmpty) {
      return EmptyState(
        icon: Icons.format_list_numbered,
        titleKey: 'panel.hierarchy.empty',
      );
    }
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      itemCount: path.length,
      onReorderItem: (oldIndex, newIndex) {
        final id = path[oldIndex];
        ref.read(documentProvider.notifier).dispatch(
          'node.reorder',
          <String, Object?>{'id': id, 'index': newIndex},
        );
      },
      itemBuilder: (context, index) {
        final id = path[index];
        final node = document.nodes[id];
        final name = '${node?['name'] ?? id}';
        return ListRow(
          key: ValueKey<String>('order-$id'),
          selected: selection.nodes.contains(id),
          onTap: () => ref.read(selectionProvider.notifier).select(id),
          leading: Text(
            '${index + 1}',
            style: TextStyle(fontSize: 10, color: AppTheme.of(context).textMuted),
          ),
          child: Text(name, style: const TextStyle(fontSize: 11.5)),
        );
      },
    );
  }

  Widget _buildFooter(DocumentState document, SelectionState selection) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.of(context).divider)),
      ),
      child: Row(
        children: <Widget>[
          SmallIconButton(
            icon: Icons.create_new_folder_outlined,
            tooltipKey: 'panel.hierarchy.newPart',
            onPressed: () => _create('part'),
          ),
          SmallIconButton(
            icon: Icons.image_outlined,
            tooltipKey: 'panel.hierarchy.newDrawable',
            onPressed: () => _create('drawable'),
          ),
          SmallIconButton(
            icon: Icons.grid_on,
            tooltipKey: 'panel.hierarchy.newWarp',
            onPressed: () => _create('warp_deformer'),
          ),
          SmallIconButton(
            icon: Icons.rotate_right,
            tooltipKey: 'panel.hierarchy.newRotation',
            onPressed: () => _create('rotation_deformer'),
          ),
          const Spacer(),
          SmallIconButton(
            icon: Icons.delete_outline,
            tooltipKey: 'common.delete',
            onPressed: selection.primary == null
                ? null
                : () => _delete(selection.primary!),
          ),
        ],
      ),
    );
  }

  Future<void> _create(String kind) async {
    final selection = ref.read(selectionProvider);
    final name = await promptDialog(
      context,
      titleKey: 'panel.hierarchy.createTitle',
      labelKey: 'common.name',
      initial: kind == 'part' ? 'Part' : 'Node',
    );
    if (name == null || name.isEmpty) return;
    String? parent = selection.primary;
    final document = ref.read(documentProvider);
    if (parent != null && '${document.nodes[parent]?['kind']}' != 'part') {
      parent = '${document.nodes[parent]?['parent']}';
    }
    await ref.read(documentProvider.notifier).dispatch(
      'node.create',
      <String, Object?>{'kind': kind, 'name': name, 'parent': ?parent},
    );
  }

  Future<void> _delete(String id) async {
    final document = ref.read(documentProvider);
    final name = '${document.nodes[id]?['name'] ?? id}';
    final ok = await confirmDialog(
      context,
      titleKey: 'panel.hierarchy.deleteTitle',
      messageKey: 'panel.hierarchy.deleteMessage',
      args: <String, String>{'name': name},
    );
    if (!ok) return;
    await ref.read(documentProvider.notifier).dispatch(
      'node.delete',
      <String, Object?>{'id': id},
    );
    ref.read(selectionProvider.notifier).clear();
  }

  Future<void> _reparent(String child, String parent) async {
    final document = ref.read(documentProvider);
    // 禁止把父节点拖进自己的子树。
    var cursor = parent;
    while (cursor.isNotEmpty) {
      if (cursor == child) return;
      cursor = '${document.nodes[cursor]?['parent'] ?? ''}';
    }
    await ref.read(documentProvider.notifier).dispatch(
      'node.reparent',
      <String, Object?>{'id': child, 'parent': parent},
    );
  }

  Future<void> _contextMenu(String id) async {
    final document = ref.read(documentProvider);
    final node = document.nodes[id];
    if (node == null) return;
    final visible = asBool(node['visible'], true);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    final position = box.localToGlobal(Offset.zero);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, 0, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          child: Text('common.rename'.tr()),
        ),
        PopupMenuItem<String>(
          value: 'visible',
          child: Text(
            (visible ? 'panel.hierarchy.hide' : 'panel.hierarchy.show').tr(),
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Text('common.duplicate'.tr()),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('common.delete'.tr()),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'rename':
        final name = await promptDialog(
          context,
          titleKey: 'common.rename',
          labelKey: 'common.name',
          initial: '${node['name'] ?? ''}',
        );
        if (name != null && name.isNotEmpty) {
          await ref.read(documentProvider.notifier).dispatch(
            'node.rename',
            <String, Object?>{'id': id, 'name': name},
          );
        }
      case 'visible':
        await ref.read(documentProvider.notifier).dispatch(
          'node.set_visible',
          <String, Object?>{'id': id, 'value': !visible},
        );
      case 'duplicate':
        await ref.read(documentProvider.notifier).dispatch(
          'node.duplicate',
          <String, Object?>{'id': id},
        );
      case 'delete':
        await _delete(id);
    }
  }

  static IconData _iconFor(String kind) {
    switch (kind) {
      case 'drawable':
        return Icons.image_outlined;
      case 'warp_deformer':
        return Icons.grid_on;
      case 'rotation_deformer':
        return Icons.rotate_right;
      default:
        return Icons.folder_outlined;
    }
  }

  static Color _colorFor(String kind, AppTokens tokens) {
    switch (kind) {
      case 'drawable':
        return tokens.accentSecondary;
      case 'warp_deformer':
      case 'rotation_deformer':
        return tokens.warning;
      default:
        return tokens.textMuted;
    }
  }
}

/// 就地重命名（双击）。
class _InlineName extends StatefulWidget {
  const _InlineName({
    required this.id,
    required this.name,
    required this.onRename,
  });

  final String id;
  final String name;
  final ValueChanged<String> onRename;

  @override
  State<_InlineName> createState() => _InlineNameState();
}

class _InlineNameState extends State<_InlineName> {
  bool _editing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void didUpdateWidget(covariant _InlineName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.name != widget.name) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return GestureDetector(
        onDoubleTap: () => setState(() => _editing = true),
        child: Text(
          widget.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
      );
    }
    return SizedBox(
      height: 20,
      child: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontSize: 11.5),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4),
          border: InputBorder.none,
        ),
        onSubmitted: (value) {
          setState(() => _editing = false);
          if (value.trim().isNotEmpty && value != widget.name) {
            widget.onRename(value.trim());
          }
        },
        onTapOutside: (_) {
          setState(() => _editing = false);
          final value = _controller.text.trim();
          if (value.isNotEmpty && value != widget.name) {
            widget.onRename(value);
          }
        },
      ),
    );
  }
}
