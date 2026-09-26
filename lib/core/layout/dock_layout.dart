/// 可停靠 / 可拖拽 / 可保存恢复的面板布局（AE0-2）。
///
/// 四个区域：左、中、右、底。区域内多面板以标签页堆叠，标签可拖到别的
/// 区域或改变顺序；区域尺寸由分隔条拖拽调整；布局可持久化。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 区域。
enum DockSlot {
  left('left'),
  center('center'),
  right('right'),
  bottom('bottom');

  const DockSlot(this.wire);

  final String wire;

  static DockSlot parse(Object? value) {
    for (final slot in DockSlot.values) {
      if (slot.wire == '$value') return slot;
    }
    return DockSlot.center;
  }
}

/// 面板声明。
class DockPanelSpec {
  const DockPanelSpec({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.defaultSlot,
    this.closable = true,
    this.hiddenByDefault = false,
    this.minSlotSize,
  });

  final String id;
  final String titleKey;
  final IconData icon;
  final DockSlot defaultSlot;
  final bool closable;
  final bool hiddenByDefault;

  /// 该面板希望所在区域的最小尺寸（宽或高）。
  final double? minSlotSize;
}

/// 布局状态。
class DockLayout {
  const DockLayout({
    required this.slots,
    required this.sizes,
    required this.hidden,
    required this.active,
  });

  /// 区域 → 面板 id 顺序。
  final Map<DockSlot, List<String>> slots;

  /// 区域 → 尺寸（左/右为宽，底为高）。
  final Map<DockSlot, double> sizes;

  /// 区域 → 是否显示。
  final Map<DockSlot, bool> hidden;

  /// 区域 → 当前激活面板 id。
  final Map<DockSlot, String?> active;

  static const Map<DockSlot, double> defaultSizes = <DockSlot, double>{
    DockSlot.left: 268,
    DockSlot.center: 0,
    DockSlot.right: 320,
    DockSlot.bottom: 248,
  };

  /// 依据面板声明生成默认布局。
  factory DockLayout.fromSpecs(List<DockPanelSpec> specs) {
    final slots = <DockSlot, List<String>>{
      for (final slot in DockSlot.values) slot: <String>[],
    };
    final hidden = <DockSlot, bool>{
      DockSlot.left: true,
      DockSlot.center: true,
      DockSlot.right: true,
      DockSlot.bottom: true,
    };
    for (final spec in specs) {
      slots[spec.defaultSlot]!.add(spec.id);
      if (!spec.hiddenByDefault) hidden[spec.defaultSlot] = false;
    }
    // 底部区域若只有隐藏面板则默认收起。
    if (slots[DockSlot.bottom]!.isEmpty) hidden[DockSlot.bottom] = true;
    return DockLayout(
      slots: slots,
      sizes: Map<DockSlot, double>.from(defaultSizes),
      hidden: hidden,
      active: <DockSlot, String?>{
        for (final slot in DockSlot.values)
          slot: slots[slot]!.isEmpty ? null : slots[slot]!.first,
      },
    );
  }

  DockLayout copyWith({
    Map<DockSlot, List<String>>? slots,
    Map<DockSlot, double>? sizes,
    Map<DockSlot, bool>? hidden,
    Map<DockSlot, String?>? active,
  }) => DockLayout(
    slots: slots ?? this.slots,
    sizes: sizes ?? this.sizes,
    hidden: hidden ?? this.hidden,
    active: active ?? this.active,
  );

  bool isVisible(DockSlot slot) =>
      !(hidden[slot] ?? true) && (slots[slot]?.isNotEmpty ?? false);

  Map<String, Object?> toJson() => <String, Object?>{
    'slots': <String, Object?>{
      for (final slot in DockSlot.values) slot.wire: slots[slot] ?? <String>[],
    },
    'sizes': <String, Object?>{
      for (final slot in DockSlot.values)
        slot.wire: sizes[slot] ?? defaultSizes[slot],
    },
    'hidden': <String, Object?>{
      for (final slot in DockSlot.values) slot.wire: hidden[slot] ?? true,
    },
    'active': <String, Object?>{
      for (final slot in DockSlot.values) slot.wire: active[slot],
    },
  };

  factory DockLayout.fromJson(Map<String, Object?> json) {
    final slots = <DockSlot, List<String>>{};
    final sizes = Map<DockSlot, double>.from(defaultSizes);
    final hidden = <DockSlot, bool>{};
    final active = <DockSlot, String?>{};
    for (final slot in DockSlot.values) {
      final rawSlots = json['slots'];
      slots[slot] = rawSlots is Map
          ? (rawSlots[slot.wire] as List?)?.map((e) => '$e').toList() ??
                <String>[]
          : <String>[];
      final rawSizes = json['sizes'];
      if (rawSizes is Map && rawSizes[slot.wire] is num) {
        sizes[slot] = (rawSizes[slot.wire] as num).toDouble();
      }
      final rawHidden = json['hidden'];
      hidden[slot] = rawHidden is Map ? rawHidden[slot.wire] != false : true;
      final rawActive = json['active'];
      active[slot] = rawActive is Map ? rawActive[slot.wire] as String? : null;
      if (active[slot] != null && !slots[slot]!.contains(active[slot])) {
        active[slot] = slots[slot]!.isEmpty ? null : slots[slot]!.first;
      }
    }
    for (final slot in DockSlot.values) {
      if (hidden[slot]! && slots[slot]!.isNotEmpty && slot == DockSlot.center) {
        hidden[slot] = false;
      }
    }
    return DockLayout(
      slots: slots,
      sizes: sizes,
      hidden: hidden,
      active: active,
    );
  }
}

/// 布局控制器。
class DockLayoutController extends Notifier<DockLayout?> {
  /// 由宿主注入的面板声明（决定默认布局）。
  List<DockPanelSpec> specs = const <DockPanelSpec>[];

  @override
  DockLayout? build() => null;

  void initialize(List<DockPanelSpec> panelSpecs, {String? savedJson}) {
    specs = panelSpecs;
    if (savedJson != null && savedJson.isNotEmpty) {
      try {
        final layout = DockLayout.fromJson(
          jsonDecode(savedJson) as Map<String, Object?>,
        );
        state = _sanitize(layout);
        return;
      } on Object {
        // 布局损坏时回退默认。
      }
    }
    state = DockLayout.fromSpecs(panelSpecs);
  }

  /// 移除已不存在的面板、补齐缺失面板。
  DockLayout _sanitize(DockLayout layout) {
    final known = specs.map((s) => s.id).toSet();
    final present = <String>{};
    final slots = <DockSlot, List<String>>{};
    for (final slot in DockSlot.values) {
      final list = (layout.slots[slot] ?? <String>[])
          .where((id) => known.contains(id))
          .toList();
      for (final id in list) {
        present.add(id);
      }
      slots[slot] = list;
    }
    for (final spec in specs) {
      if (present.contains(spec.id)) continue;
      slots[spec.defaultSlot]!.add(spec.id);
    }
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    for (final slot in DockSlot.values) {
      hidden[slot] = (hidden[slot] ?? true) || slots[slot]!.isEmpty;
    }
    hidden[DockSlot.center] = false;
    final active = Map<DockSlot, String?>.from(layout.active);
    for (final slot in DockSlot.values) {
      if (active[slot] == null || !slots[slot]!.contains(active[slot])) {
        active[slot] = slots[slot]!.isEmpty ? null : slots[slot]!.first;
      }
    }
    return layout.copyWith(slots: slots, hidden: hidden, active: active);
  }

  DockLayout? get _current => state;

  void setActive(DockSlot slot, String id) {
    final layout = _current;
    if (layout == null) return;
    final active = Map<DockSlot, String?>.from(layout.active);
    active[slot] = id;
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    hidden[slot] = false;
    state = layout.copyWith(active: active, hidden: hidden);
  }

  void setSize(DockSlot slot, double size) {
    final layout = _current;
    if (layout == null) return;
    final minimum = switch (slot) {
      DockSlot.left || DockSlot.right => 160.0,
      DockSlot.bottom => 120.0,
      DockSlot.center => 0.0,
    };
    final maximum = switch (slot) {
      DockSlot.left || DockSlot.right => 640.0,
      DockSlot.bottom => 720.0,
      DockSlot.center => 0.0,
    };
    final sizes = Map<DockSlot, double>.from(layout.sizes);
    sizes[slot] = size.clamp(minimum, maximum);
    state = layout.copyWith(sizes: sizes);
  }

  void showPanel(String id, {DockSlot? slot}) {
    final layout = _current;
    if (layout == null) return;
    final target = slot ?? _slotOf(layout, id) ?? _defaultSlotOf(id);
    if (target == null) return;
    final slots = <DockSlot, List<String>>{
      for (final entry in layout.slots.entries)
        entry.key: List<String>.from(entry.value),
    };
    for (final entry in slots.entries) {
      if (entry.key != target) entry.value.remove(id);
    }
    if (!slots[target]!.contains(id)) slots[target]!.add(id);
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    hidden[target] = false;
    final active = Map<DockSlot, String?>.from(layout.active);
    active[target] = id;
    state = layout.copyWith(slots: slots, hidden: hidden, active: active);
  }

  void hidePanel(String id) {
    final layout = _current;
    if (layout == null) return;
    final slots = <DockSlot, List<String>>{
      for (final entry in layout.slots.entries)
        entry.key: List<String>.from(entry.value)..remove(id),
    };
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    for (final slot in DockSlot.values) {
      if (slots[slot]!.isEmpty) hidden[slot] = true;
    }
    final active = Map<DockSlot, String?>.from(layout.active);
    for (final slot in DockSlot.values) {
      if (active[slot] == id) {
        active[slot] = slots[slot]!.isEmpty ? null : slots[slot]!.first;
      }
    }
    state = layout.copyWith(slots: slots, hidden: hidden, active: active);
  }

  void togglePanel(String id) {
    final layout = _current;
    if (layout == null) return;
    if (_slotOf(layout, id) != null) {
      hidePanel(id);
    } else {
      showPanel(id);
    }
  }

  void toggleSlot(DockSlot slot) {
    final layout = _current;
    if (layout == null) return;
    if (slot == DockSlot.center) return;
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    hidden[slot] = !(hidden[slot] ?? true);
    state = layout.copyWith(hidden: hidden);
  }

  /// 拖拽：把面板移动到目标区域的目标位置。
  void movePanel(String id, DockSlot target, int index) {
    final layout = _current;
    if (layout == null) return;
    final slots = <DockSlot, List<String>>{
      for (final entry in layout.slots.entries)
        entry.key: List<String>.from(entry.value)..remove(id),
    };
    final list = slots[target]!;
    list.insert(index.clamp(0, list.length), id);
    final hidden = Map<DockSlot, bool>.from(layout.hidden);
    hidden[target] = false;
    final active = Map<DockSlot, String?>.from(layout.active);
    active[target] = id;
    for (final slot in DockSlot.values) {
      if (active[slot] != null && !slots[slot]!.contains(active[slot])) {
        active[slot] = slots[slot]!.isEmpty ? null : slots[slot]!.first;
      }
      if (slots[slot]!.isEmpty) hidden[slot] = true;
    }
    hidden[DockSlot.center] = false;
    state = layout.copyWith(slots: slots, hidden: hidden, active: active);
  }

  void reset() {
    if (specs.isEmpty) return;
    state = DockLayout.fromSpecs(specs);
  }

  DockSlot? _slotOf(DockLayout layout, String id) {
    for (final entry in layout.slots.entries) {
      if (entry.value.contains(id)) return entry.key;
    }
    return null;
  }

  DockSlot? _defaultSlotOf(String id) {
    for (final spec in specs) {
      if (spec.id == id) return spec.defaultSlot;
    }
    return null;
  }

  String? exportJson() {
    final layout = _current;
    if (layout == null) return null;
    return jsonEncode(layout.toJson());
  }
}

final dockLayoutProvider = NotifierProvider<DockLayoutController, DockLayout?>(
  DockLayoutController.new,
);
