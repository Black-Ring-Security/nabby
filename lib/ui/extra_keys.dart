import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../services/session.dart';

/// Termux-style row of keys missing from phone keyboards.
class ExtraKeysBar extends StatelessWidget {
  const ExtraKeysBar({super.key, required this.session, required this.onPaste});

  final TerminalSession session;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget key(String label,
        {VoidCallback? onTap, bool active = false, IconData? icon, bool repeat = false}) {
      return _Key(
        label: label,
        icon: icon,
        active: active,
        repeat: repeat,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
      );
    }

    void k(TerminalKey t) => session.sendKey(t);
    void text(String s) => session.terminal.textInput(s);

    final row1 = [
      key('ESC', onTap: () => k(TerminalKey.escape)),
      key('TAB', onTap: () => k(TerminalKey.tab)),
      key('CTRL', active: session.ctrlLatched, onTap: session.toggleCtrl),
      key('ALT', active: session.altLatched, onTap: session.toggleAlt),
      key('↑', repeat: true, onTap: () => k(TerminalKey.arrowUp)),
      key('↓', repeat: true, onTap: () => k(TerminalKey.arrowDown)),
      key('←', repeat: true, onTap: () => k(TerminalKey.arrowLeft)),
      key('→', repeat: true, onTap: () => k(TerminalKey.arrowRight)),
    ];
    final row2 = [
      key('/', onTap: () => text('/')),
      key('-', onTap: () => text('-')),
      key('|', onTap: () => text('|')),
      key('~', onTap: () => text('~')),
      key('HOME', onTap: () => k(TerminalKey.home)),
      key('END', onTap: () => k(TerminalKey.end)),
      key('PGUP', onTap: () => k(TerminalKey.pageUp)),
      key('PGDN', onTap: () => k(TerminalKey.pageDown)),
      key('^C', onTap: () => text('\x03')),
      key('^D', onTap: () => text('\x04')),
      key('^Z', onTap: () => text('\x1a')),
      key('^L', onTap: () => text('\x0c')),
      key('^R', onTap: () => text('\x12')),
      key('DEL', onTap: () => k(TerminalKey.delete)),
      for (var i = 1; i <= 12; i++)
        key('F$i', onTap: () => k(TerminalKey.values.byName('f$i'))),
      key('', icon: Icons.content_paste, onTap: onPaste),
    ];
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 40, child: Row(children: [for (final w in row1) Expanded(child: w)])),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final w in row2) SizedBox(width: 52, child: w),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
    this.repeat = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool active;
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;
  bool _repeating = false;

  Future<void> _startRepeat() async {
    if (!widget.repeat) return;
    _repeating = true;
    await Future.delayed(const Duration(milliseconds: 50));
    while (_repeating && mounted) {
      widget.onTap();
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = widget.active ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPressStart: (_) => _startRepeat(),
      onLongPressEnd: (_) {
        _repeating = false;
        setState(() => _down = false);
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active
              ? cs.primary
              : _down
                  ? cs.onSurface.withValues(alpha: 0.18)
                  : cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: widget.icon != null
            ? Icon(widget.icon, size: 18, color: fg)
            : Text(widget.label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg,
                    fontFamily: 'SourceCodePro')),
      ),
    );
  }
}
