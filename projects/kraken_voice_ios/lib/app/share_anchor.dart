import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// iPad presents sharing as a popover and requires an on-screen source rect.
abstract final class AnchoredShare {
  static Rect _origin(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return const Rect.fromLTWH(1, 1, 1, 1);
  }

  static Future<ShareResult> files(
    BuildContext context,
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
  }) => Share.shareXFiles(
    files,
    subject: subject,
    text: text,
    sharePositionOrigin: sharePositionOrigin ?? _origin(context),
  );

  static Future<ShareResult> text(
    BuildContext context,
    String text, {
    String? subject,
  }) => Share.share(
    text,
    subject: subject,
    sharePositionOrigin: _origin(context),
  );
}
