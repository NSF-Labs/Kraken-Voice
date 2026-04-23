# User-Facing Terminology Rename Inventory

## "Workspace" strings

### `lib/shell/ui/dashboard_screen.dart`
- Line 141: `'Recent Workspaces',`
- Line 297: `'No workspaces yet.\nCreate one to organize source data.',`
- Line 369: `'New Workspace ${_workspaces.length + 1}',`

### `lib/shell/ui/workspace_detail_screen.dart`
- Line 54: `SnackBar(content: Text('Failed to load workspace data: $e')),`
- Line 119: `'Rename Workspace',`
- Line 126: `hintText: 'Workspace Name',`
- Line 193: `'Delete Workspace',`
- Line 199: `'Are you sure? Deleted workspaces and their documents cannot be retrieved.',`
- Line 282: `title: Text(_workspace?.name ?? 'Workspace Details'),`
- Line 305: `? const Center(child: Text('Workspace not found'))`
- Line 370: `'No documents in this workspace.\nTap + to import one.',`

## "Spoke Output" and related strings
No occurrences found in user-facing contexts.

## Ambiguous Cases
- None found during initial inventory. All the above are clear user-facing cases.

## Notes
- `lib/kernel/` contains code-level identifiers which will NOT be renamed.
- `app_router.dart` and `settings_screen.dart` were checked but contained no user-facing occurrences.
- `KRAKEN_SECURITY_PROTOCOL.md` contains some references to workspaces, which are considered developer-facing documentation and will be updated with a terminology note.
