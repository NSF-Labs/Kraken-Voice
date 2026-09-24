import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../kernel/kernel.dart';
import '../design/tokens.dart';

/// Shows the Krak-EN Voice upgrade / purchase modal.
///
/// Identical to the dialog triggered by tapping the free-tier countdown timer
/// on the dashboard. Can be invoked from any screen with a [BuildContext] that
/// provides [EntitlementService] via `RepositoryProvider`.
///
/// If [reachedLimit] is true the dialog is non-dismissible and tailored for the
/// "your 20-min recording has been saved" scenario.
///
/// Optionally pass [onPurchaseStateChanged] to run state-update logic after a
/// purchase or restore action completes.
void showUpgradeModal(
  BuildContext context, {
  bool reachedLimit = false,
  VoidCallback? onPurchaseStateChanged,
}) {
  showDialog(
    context: context,
    barrierDismissible: !reachedLimit,
    builder: (ctx) => AlertDialog(
      backgroundColor: KrakenColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        reachedLimit ? 'Recording Limit Reached' : 'Upgrade to Pro',
        style: KrakenText.displayMd(),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reachedLimit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Your 20-minute recording has been saved.',
                style: KrakenText.bodyMd().copyWith(
                  color: KrakenColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            'Upgrade to unlock unlimited recording length, '
            'custom exports, and more — '
            'one-time purchase of \$19.95. No subscriptions.',
            style: KrakenText.bodyMd(),
          ),
          const SizedBox(height: 12),
          // Feature bullets
          ...['⏱  Unlimited recording length',
              '🗣  Speaker identification (coming soon)',
              '📄  PDF, DOCX, Markdown export',
              '🎨  Custom branding & export options',
              '💬  AI chat with your meetings',
          ].map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(f, style: KrakenText.bodySm()),
              )),
        ],
      ),
      actions: [
        if (!reachedLimit)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maybe Later'),
          ),
        if (reachedLimit)
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maybe Later'),
          ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final entitlements =
                RepositoryProvider.of<EntitlementService>(context, listen: false);
            await entitlements.restorePurchases();
            entitlements.changes.first.then((_) {
              onPurchaseStateChanged?.call();
            });
          },
          child: const Text('Restore Purchase'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final entitlements =
                RepositoryProvider.of<EntitlementService>(context, listen: false);
            final success = await entitlements.purchaseFullUnlock();
            if (!success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Purchase could not be started. Please try again.')),
              );
            }
            entitlements.changes.first.then((_) {
              onPurchaseStateChanged?.call();
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: KrakenColors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Upgrade — \$19.95'),
        ),
      ],
    ),
  );
}
