import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../kernel/kernel.dart';
import '../design/tokens.dart';

class LibraryPickerSheet extends StatelessWidget {
  final List<Workspace> workspaces;
  final Workspace? activeWorkspace;
  final void Function(Workspace) onSelected;
  final VoidCallback onCreateNew;

  const LibraryPickerSheet({
    super.key,
    required this.workspaces,
    required this.activeWorkspace,
    required this.onSelected,
    required this.onCreateNew,
  });

  static Future<void> show(BuildContext context) async {
    HapticFeedback.lightImpact();

    // Load workspaces
    final workspaceService = context.read<WorkspaceService>();
    final workspaces = await workspaceService.listAllWorkspaces();

    // Since we don't have a single source of truth for "active workspace" outside
    // the dashboard screen right now, we will just pass null or find the first one.
    // Ideally the current path or state would give us the active workspace.
    // For now, if we are in a workspace, we could extract it from GoRouter state,
    // but a simple UI for the picker is enough to just list them.
    Workspace? activeWorkspace;
    // ... we can omit highlighting the active one if we don't have it in scope easily,
    // or just let it be null.

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KrakenRadius.xl),
        ),
      ),
      builder: (sheetCtx) => LibraryPickerSheet(
        workspaces: workspaces,
        activeWorkspace: activeWorkspace,
        onSelected: (workspace) {
          Navigator.of(sheetCtx).pop();
          context.push('/workspace/${workspace.id}');
        },
        onCreateNew: () async {
          Navigator.of(sheetCtx).pop();
          final newW = await workspaceService.createWorkspace(
            'New Library ${workspaces.length + 1}',
          );
          if (context.mounted) {
            context.push('/workspace/${newW.id}');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KrakenSpacing.s7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Libraries', style: KrakenText.displayLg()),
            const SizedBox(height: KrakenSpacing.s5),
            ...workspaces.map(
              (w) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(w.name, style: KrakenText.bodyLg()),
                trailing: w.id == activeWorkspace?.id
                    ? const Icon(
                        Icons.check,
                        color: KrakenColors.accent,
                        size: 18,
                      )
                    : null,
                onTap: () => onSelected(w),
              ),
            ),
            const Divider(color: KrakenColors.border, height: KrakenSpacing.s7),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.add,
                color: KrakenColors.accent,
                size: 20,
              ),
              title: Text(
                'New Library',
                style: KrakenText.bodyLg(color: KrakenColors.accent),
              ),
              onTap: onCreateNew,
            ),
          ],
        ),
      ),
    );
  }
}
