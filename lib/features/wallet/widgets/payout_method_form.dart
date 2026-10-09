import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/layout/app_spacing.dart';
import '../../../theme/halchal_colors.dart';
import 'bank_card_preview.dart';

final _ifscPattern = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
final _panPattern = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
final _accountPattern = RegExp(r'^\d{6,20}$');
final _upiPattern = RegExp(r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z0-9]{2,64}$');

/// Bank/UPI details capture form, shared by the payout methods bottom sheet
/// and the inline "add a payout method" flow on the withdraw screen.
class PayoutMethodForm extends ConsumerStatefulWidget {
  const PayoutMethodForm({
    super.key,
    required this.onSaved,
    this.title,
  });

  final void Function(PayoutMethod method) onSaved;
  final String? title;

  @override
  ConsumerState<PayoutMethodForm> createState() => _PayoutMethodFormState();
}

class _PayoutMethodFormState extends ConsumerState<PayoutMethodForm> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'bank';
  final _labelController = TextEditingController();
  final _holderController = TextEditingController();
  final _accountController = TextEditingController();
  final _confirmAccountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _panController = TextEditingController();
  bool _saving = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_labelController, _holderController, _accountController, _ifscController]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() => setState(() {});

  void _toggleRevealed() => setState(() => _revealed = !_revealed);

  @override
  void dispose() {
    _labelController.dispose();
    _holderController.dispose();
    _accountController.dispose();
    _confirmAccountController.dispose();
    _ifscController.dispose();
    _panController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final method = await ref.read(apiClientProvider).createPayoutMethod(
            type: _type,
            label: _labelController.text.trim(),
            accountHolderName: _holderController.text.trim(),
            account: _accountController.text.trim(),
            ifscCode: _type == 'bank'
                ? _ifscController.text.trim().toUpperCase()
                : null,
            // The API requires a PAN for bank accounts (used for tax reporting
            // on payouts); this form used to omit it, so adding a bank here
            // was always rejected.
            panNumber: _type == 'bank'
                ? _panController.text.trim().toUpperCase()
                : null,
          );
      if (!mounted) return;
      widget.onSaved(method);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vc = HalchalColors.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: vc.onSurface,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.account_balance, size: 18),
                  label: const Text('Bank account'),
                  selected: _type == 'bank',
                  onSelected: (_) => setState(() => _type = 'bank'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.phone_android, size: 18),
                  label: const Text('UPI'),
                  selected: _type == 'upi',
                  onSelected: (_) => setState(() => _type = 'upi'),
                ),
              ),
            ],
          ),
          if (_type == 'bank') ...[
            const SizedBox(height: 16),
            BankCardPreview(
              bankName: _labelController.text,
              holderName: _holderController.text,
              accountNumber: _accountController.text,
              ifsc: _ifscController.text,
              revealed: _revealed,
            ),
            if (_accountController.text.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              BankCardRevealToggle(
                revealed: _revealed,
                onTap: _toggleRevealed,
              ),
            ],
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _labelController,
            decoration: InputDecoration(
              labelText: _type == 'upi' ? 'Label (e.g. Personal UPI)' : 'Label (e.g. HDFC Bank)',
              filled: true,
              fillColor: vc.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Enter a label' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _holderController,
            decoration: InputDecoration(
              labelText: 'Account holder name',
              hintText: 'As it appears on your bank account',
              filled: true,
              fillColor: vc.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Enter the account holder name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _accountController,
            keyboardType:
                _type == 'upi' ? TextInputType.text : TextInputType.number,
            inputFormatters:
                _type == 'upi' ? null : [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _type == 'upi' ? 'UPI ID' : 'Account number',
              hintText: _type == 'upi' ? 'name@bank' : '1234567890',
              filled: true,
              fillColor: vc.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (_type == 'upi') {
                return _upiPattern.hasMatch(s) ? null : 'Enter a valid UPI ID (name@bank)';
              }
              return _accountPattern.hasMatch(s) ? null : 'Enter your account number (6-20 digits)';
            },
          ),
          if (_type == 'bank') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmAccountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Confirm account number',
                hintText: 'Re-enter account number',
                filled: true,
                fillColor: vc.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => (v?.trim() ?? '') == _accountController.text.trim()
                  ? null
                  : 'Account numbers do not match',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _panController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextInputFormatter()],
              decoration: InputDecoration(
                labelText: 'PAN',
                hintText: 'ABCPV1234D',
                filled: true,
                fillColor: vc.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => _panPattern.hasMatch(v?.trim() ?? '') ? null : 'Enter a valid PAN',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ifscController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextInputFormatter()],
              decoration: InputDecoration(
                labelText: 'IFSC code',
                hintText: 'HDFC0001234',
                filled: true,
                fillColor: vc.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) {
                if (v == null || !_ifscPattern.hasMatch(v.trim())) {
                  return 'Enter a valid IFSC code (e.g. HDFC0001234)';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: vc.onPrimary),
                  )
                : const Text('Add method'),
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
