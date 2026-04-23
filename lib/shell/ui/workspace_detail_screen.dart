import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../kernel/kernel.dart';
import 'kraken_shell_frame.dart';

class WorkspaceDetailScreen extends StatefulWidget {
  final String workspaceId;

  const WorkspaceDetailScreen({super.key, required this.workspaceId});

  @override
  State<WorkspaceDetailScreen> createState() => _WorkspaceDetailScreenState();
}

class _WorkspaceDetailScreenState extends State<WorkspaceDetailScreen> {
  Workspace? _workspace;
  List<Document> _documents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final workspaceService = context.read<WorkspaceService>();
    try {
      final ws = await workspaceService.getWorkspace(widget.workspaceId);
      final docs = await workspaceService.listDocumentsForShell(
        widget.workspaceId,
      );
      if (mounted) {
        setState(() {
          _workspace = ws;
          _documents = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load library data: $e')),
        );
      }
    }
  }

  Future<void> _importDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      withData: true,
    );

    if (result != null) {
      final file = result.files.single;
      Uint8List data;

      if (file.bytes != null) {
        data = file.bytes!;
      } else if (file.path != null) {
        data = await File(file.path!).readAsBytes();
      } else {
        return;
      }

      final filename = file.name;
      // Extract extension for a rudimentary mime type guess, or just fallback
      final extension = filename.split('.').last.toLowerCase();
      String mimeType = 'application/octet-stream';
      if (extension == 'pdf') {
        mimeType = 'application/pdf';
      } else if (extension == 'png')
        mimeType = 'image/png';
      else if (extension == 'jpg' || extension == 'jpeg')
        mimeType = 'image/jpeg';
      else if (extension == 'txt')
        mimeType = 'text/plain';

      final workspaceService = context.read<WorkspaceService>();

      try {
        await workspaceService.importDocument(
          widget.workspaceId,
          filename,
          data,
          mimeType: mimeType,
        );
        // Reload to show the new document
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to import document: $e')),
          );
        }
      }
    }
  }

  Future<void> _renameWorkspace() async {
    final controller = TextEditingController(text: _workspace?.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Rename Library',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Library Name',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF6366F1)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName != null &&
        newName.trim().isNotEmpty &&
        newName != _workspace?.name) {
      try {
        await context.read<WorkspaceService>().renameWorkspace(
          widget.workspaceId,
          newName.trim(),
        );
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
        }
      }
    }
  }

  Future<void> _deleteWorkspace() async {
    final prefs = PreferencesService();
    final bool hideWarning = await prefs.getBool(
      'hide_workspace_delete_warning',
    );

    bool shouldDelete = hideWarning;

    if (!hideWarning) {
      bool doNotShowAgain = false;
      shouldDelete =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return StatefulBuilder(
                builder: (context, setState) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2E),
                    title: const Text(
                      'Delete Library',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Are you sure? Deleted libraries and their documents cannot be retrieved.',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: doNotShowAgain,
                              onChanged: (val) {
                                setState(() {
                                  doNotShowAgain = val ?? false;
                                });
                              },
                              activeColor: const Color(0xFF6366F1),
                            ),
                            Expanded(
                              child: Text(
                                'Do not show again',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (doNotShowAgain) {
                            prefs.setBool(
                              'hide_workspace_delete_warning',
                              true,
                            );
                          }
                          Navigator.pop(context, true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  );
                },
              );
            },
          ) ??
          false;
    }

    if (shouldDelete) {
      try {
        await context.read<WorkspaceService>().deleteWorkspace(
          widget.workspaceId,
        );
        if (mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KrakenShellFrame(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_workspace?.name ?? 'Library Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          actions: [
            if (_workspace != null) ...[
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white70),
                onPressed: _renameWorkspace,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _deleteWorkspace,
              ),
            ],
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF818CF8)),
              )
            : _workspace == null
            ? const Center(child: Text('Library not found'))
            : Column(
                children: [
                  _buildWorkspaceHeader(),
                  Expanded(child: _buildDocumentsList()),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _importDocument,
          backgroundColor: const Color(0xFF6366F1),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Import Document'),
        ),
      ),
    );
  }

  Widget _buildWorkspaceHeader() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SECURE VAULT AREA',
            style: TextStyle(
              color: Color(0xFF34D399),
              fontSize: 12,
              letterSpacing: 2.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _workspace!.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Created on ${_workspace!.createdAt.toLocal().toString().split('.')[0]}",
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsList() {
    if (_documents.isEmpty) {
      return Center(
        child: Text(
          'No documents in this library.\nTap + to import one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: _documents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = _documents[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.description, color: Color(0xFFA5B4FC)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.filename,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doc.mimeType ?? 'Unknown Type',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
