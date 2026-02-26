import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../ide_controller.dart';
import 'code_editor.dart';

/// Dispatches to the correct right-pane viewer based on [IdeController.displayMode].
class IdeFileViewer extends StatelessWidget {
  final IdeController ctrl;
  const IdeFileViewer({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    if (ctrl.isLoadingFile) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (ctrl.displayMode) {
      case FileDisplayMode.image:
        if (ctrl.fileBytes != null) {
          return Center(
            child: InteractiveViewer(child: Image.memory(ctrl.fileBytes!)),
          );
        }
      case FileDisplayMode.pdf:
        if (ctrl.fileBytes != null) {
          return SfPdfViewer.memory(ctrl.fileBytes!);
        }
      case FileDisplayMode.unsupported:
        return const Center(child: Text('Unsupported file format'));
      case FileDisplayMode.processLogs:
      // Process logs are now shown in the persistent bottom pane; if this
      // mode is somehow still active just fall through to the default.
      case FileDisplayMode.code:
        if (ctrl.codeController != null) {
          return IdeCodeEditor(ctrl: ctrl);
        }
    }

    return const Center(child: Text('Select a file or task to view'));
  }
}
