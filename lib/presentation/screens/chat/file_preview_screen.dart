import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The last look before a file leaves the phone: what it is, how big,
/// and a rename box — because the name is the one thing worth editing
/// on a document. Nothing is uploaded unseen.
/// ─────────────────────────────────────────────────────────────────────────────

/// Shows [name] ([size] bytes) in the send-preview screen. Resolves with
/// the (possibly renamed) file name to send, or null when the user backs out.
Future<String?> openFilePreview(
  BuildContext context, {
  required String name,
  required int size,
}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FilePreviewScreen(name: name, size: size),
    ),
  );
}

class FilePreviewScreen extends StatefulWidget {
  final String name;
  final int size;
  const FilePreviewScreen({super.key, required this.name, required this.size});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);

  String get _extension {
    final dot = widget.name.lastIndexOf('.');
    if (dot == -1 || dot == widget.name.length - 1) return 'file';
    return widget.name.substring(dot + 1).toLowerCase();
  }

  IconData get _icon {
    switch (_extension) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'ods':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
      case 'flac':
      case 'opus':
        return Icons.audio_file_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String get _sizeLabel {
    final s = widget.size;
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Preview',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Container(
                height: 118,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: BookNestColors.cyan.withOpacity(.10),
                  border:
                      Border.all(color: BookNestColors.cyan.withOpacity(.35)),
                ),
                child: Icon(_icon, color: BookNestColors.cyan, size: 54),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('${_extension.toUpperCase()}  ·  $_sizeLabel',
                    style: const TextStyle(
                        color: BookNestColors.cyan,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4)),
              ),
              const SizedBox(height: 22),
              Text('Name',
                  style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                maxLength: 120,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(120),
                  FilteringTextInputFormatter.deny(RegExp(r'[/\\]')),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.edit_rounded,
                      size: 18, color: BookNestColors.cyan),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: BookNestColors.cyan,
                        foregroundColor: BookNestColors.navyDeep,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () {
                        final clean =
                            _name.text.trim().isEmpty ? widget.name : _name.text.trim();
                        Navigator.of(context).pop(clean);
                      },
                      child: const Text('Send',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
