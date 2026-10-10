import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/token_colors.dart';
import '../../../theme/halchal_colors.dart';
import 'auth_ui.dart';
import 'otp_status_icon.dart';

/// Six separate boxes; focus moves forward on digit, back on delete.
class OtpPinInput extends StatefulWidget {
  const OtpPinInput({
    super.key,
    required this.onCompleted,
    required this.status,
    this.enabled = true,
  });

  final ValueChanged<String> onCompleted;
  final OtpStatus status;
  final bool enabled;

  @override
  State<OtpPinInput> createState() => OtpPinInputState();
}

class OtpPinInputState extends State<OtpPinInput> {
  static const _length = 6;
  final _nodes = List.generate(_length, (_) => FocusNode());
  final _controllers = List.generate(_length, (_) => TextEditingController());

  final _previous = List.filled(_length, '');

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _previous.fillRange(0, _length, '');
    if (mounted) setState(() {});
    _nodes.first.requestFocus();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _notifyIfComplete() {
    final code = _code;
    if (code.length == _length) {
      widget.onCompleted(code);
    }
  }

  void _onChanged(int index, String value) {
    var digit = value.replaceAll(RegExp(r'\D'), '');
    final hadDigit = _previous[index].isNotEmpty;
    // Typing over a filled box gives 2 chars: keep the new one. Anything longer
    // (or 2 chars into an empty box) is a paste / SMS autofill: spread it.
    if (digit.length > 2 || (digit.length == 2 && !hadDigit)) {
      _spread(index, digit);
      return;
    }
    if (digit.length > 1) digit = digit[digit.length - 1];
    _controllers[index].text = digit;
    _controllers[index].selection = TextSelection.collapsed(offset: digit.length);
    _previous[index] = digit;

    if (digit.isNotEmpty && index < _length - 1) {
      _nodes[index + 1].requestFocus();
    }
    if (digit.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }

    setState(() {});
    _notifyIfComplete();
  }

  /// Fills the boxes with a pasted code. A full-length code always starts at the
  /// first box; a shorter one starts at the box it was pasted into.
  void _spread(int index, String digits) {
    final start = digits.length >= _length ? 0 : index;
    final chars = digits.length > _length ? digits.substring(0, _length) : digits;
    for (var i = 0; i < _length; i++) {
      final pos = i - start;
      if (pos >= 0 && pos < chars.length) {
        _controllers[i].text = chars[pos];
        _previous[i] = chars[pos];
      }
    }
    final last = (start + chars.length - 1).clamp(0, _length - 1);
    _nodes[last].requestFocus();
    setState(() {});
    _notifyIfComplete();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _nodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final stateColor = switch (widget.status) {
      OtpStatus.idle => null,
      OtpStatus.verifying => vc.warning,
      OtpStatus.verified => vc.money,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_length, (i) {
        final hasFocus = _nodes[i].hasFocus;
        final filled = _controllers[i].text.isNotEmpty;
        return Container(
          decoration: stateColor == null
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(ViralCutTokenRadius.md),
                  boxShadow: [
                    BoxShadow(color: stateColor.withValues(alpha: 0.4), blurRadius: 8),
                  ],
                ),
          child: SizedBox(
            width: 46,
            height: 54,
            child: Focus(
              onKeyEvent: (node, event) => _onKey(i, event),
              child: TextField(
                controller: _controllers[i],
                focusNode: _nodes[i],
                enabled: widget.enabled,
                autofocus: i == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                // No maxLength: it would cut a pasted code down to one digit
                // before onChanged sees it. _onChanged keeps each box to one.
                style: AuthUi.bodyFont(context).copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: vc.onSurface,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: vc.surface,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ViralCutTokenRadius.md),
                    borderSide: BorderSide(color: vc.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ViralCutTokenRadius.md),
                    borderSide: BorderSide(
                      color: stateColor ?? (filled || hasFocus ? primary : vc.border),
                      width: hasFocus ? 1.5 : 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ViralCutTokenRadius.md),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          ),
        );
      }),
    );
  }
}
