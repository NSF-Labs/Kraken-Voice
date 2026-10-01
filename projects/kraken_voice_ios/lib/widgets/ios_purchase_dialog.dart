import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../kernel/entitlements/ios_entitlement_service.dart';

Future<void> showIOSPurchaseDialog(
  BuildContext context,
  IOSEntitlementService store,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => StreamBuilder(
      stream: store.changes,
      builder: (context, _) => AlertDialog(
        title: Text(
          store.lifetimeUnlocked ? 'Lifetime access unlocked' : 'Krak-EN Voice',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.lifetimeUnlocked
                    ? 'Your Apple Account owns the full unlock.'
                    : store.trialActive
                    ? '${store.trialDaysRemaining} days remaining in your free trial.'
                    : store.trialStarted
                    ? 'Your 30-day trial has ended.'
                    : 'Try all features free for 30 days.',
              ),
              const SizedBox(height: 12),
              Text(
                'After the trial, a one-time ${store.fullUnlockPrice} purchase unlocks recording and AI processing for life. No subscription or automatic charge. You can still open, play, export and delete saved work without purchasing.',
              ),
              if (!store.isStoreAvailable && !store.lifetimeUnlocked)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Connect to the App Store to load available purchases.',
                  ),
                ),
              if (store.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    store.error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              if (store.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(store.message!),
                ),
              if (store.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              TextButton(
                onPressed: () async {
                  if (!await launchUrl(
                        Uri.parse(kPrivacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
                      ) &&
                      context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open the privacy policy.'),
                      ),
                    );
                },
                child: const Text('Privacy Policy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: store.busy ? null : store.restorePurchases,
            child: const Text('Restore Purchases'),
          ),
          TextButton(
            onPressed: store.busy ? null : store.redeemCode,
            child: const Text('Redeem Offer Code'),
          ),
          if (!store.isStoreAvailable)
            TextButton(
              onPressed: store.busy ? null : store.refresh,
              child: const Text('Retry App Store'),
            ),
          if (!store.lifetimeUnlocked && !store.trialStarted)
            FilledButton(
              onPressed:
                  store.busy || !store.canStartTrial || !store.canPurchase
                  ? null
                  : store.startTrial,
              child: const Text('Start 30-day Trial — Free'),
            ),
          if (!store.lifetimeUnlocked)
            FilledButton(
              onPressed: store.busy || !store.canPurchase
                  ? null
                  : store.purchaseFullUnlock,
              child: Text('Unlock for Life — ${store.fullUnlockPrice}'),
            ),
        ],
      ),
    ),
  );
}
