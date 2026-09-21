import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../../components/booknest_ui.dart';
import '../../components/comic_canvas.dart';

/// The Anime Studio — BookNest's comic creation suite. Build a page from
/// panel grids, drop in art and lettering, then publish as a tiny JSON
/// document the whole world can read. Drafts live on this device until
/// they are published; nothing is ever lost mid-drawing.
class ComicEditorScreen extends StatefulWidget {
  final String? comicId; // editing an already-published comic
  final String? initialTitle;
  final List<ComicPageData>? initialPages;

  const ComicEditorScreen({
    super.key,
    this.comicId,
    this.initialTitle,
    this.initialPages,
  });

  @override
  State<ComicEditorScreen> createState() => _ComicEditorScreenState();
}

class _ComicEditorScreenState extends State<ComicEditorScreen> {
  static const String _draftKey = 'anime_studio_draft_v1';

  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle ?? '');
  late List<ComicPageData> _pages =
      widget.initialPages != null && widget.initialPages!.isNotEmpty
          ? List.of(widget.initialPages!)
          : [
              ComicPageData(
                  pageNumber: 1, panels: panelsForGrid('Classic 2×2')),
            ];
  int _page = 0;
  bool _saving = false;
  bool _uploading = false;
  String _grid = 'Classic 2×2';

  @override
  void initState() {
    super.initState();
    _restoreDraftIfAny();
  }

  Future<void> _restoreDraftIfAny() async {
    if (widget.initialPages != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final saved = jsonDecode(raw) as Map;
      final pages =
          ComicPageData.listFromJson((saved['pages'] as List?) ?? []);
      final title = saved['title']?.toString() ?? '';
      if (pages.isEmpty && title.isEmpty) return;
      if (!mounted) return;
      setState(() {
        if (pages.isNotEmpty) _pages = pages;
        if (_title.text.isEmpty && title.isNotEmpty) _title.text = title;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Draft restored — it was kept safe on this device.')));
    } catch (_) {}
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _draftKey,
        jsonEncode(
            {'title': _title.text, 'pages': ComicPageData.listToJson(_pages)}),
      );
    } catch (_) {}
  }

  // ── art upload (Cloudinary, per BookNest media law) ──
  Future<String?> _pickAndUpload(ComicPanelData panel) async {
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 86);
      if (picked == null) return null;
      if (mounted) setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final url = await CloudinaryService.uploadImage(
        bytes: bytes,
        folder: 'anime',
        publicId:
            'comic-${widget.comicId ?? 'draft'}-${panel.id}-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      );
      return url;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('That picture could not be uploaded — try again.')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<ComicElementData?> _editLettering(ComicElementData current) {
    final controller = TextEditingController(text: current.text);
    var style = current.style;
    const styles = {
      'roundedBox': 'Speech',
      'screamBurst': 'Scream',
      'thoughtCloud': 'Thought',
    };
    return showDialog<ComicElementData>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
              current.text.isEmpty || current.text == 'Say something…'
                  ? 'Add lettering'
                  : 'Edit lettering',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                decoration: const InputDecoration(
                    hintText: 'What do they say?',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              if (current.type == 'speech_bubble') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final entry in styles.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(entry.value,
                              style: const TextStyle(fontSize: 12)),
                          selected: style == entry.key,
                          onSelected: (_) =>
                              setDialogState(() => style = entry.key),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, current.copyWith(text: '')),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.redAccent)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: BookNestColors.cyan),
              onPressed: () => Navigator.pop(dialogContext,
                  current.copyWith(text: controller.text, style: style)),
              child: const Text('Done',
                  style: TextStyle(
                      color: BookNestColors.navy,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ── publishing ──
  Future<void> _publish() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give your comic a title first.')));
      return;
    }
    final hasContent = _pages
        .any((p) => p.panels.any((panel) => panel.elements.isNotEmpty));
    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Add some art or lettering to at least one panel.')));
      return;
    }
    setState(() => _saving = true);
    String? cover;
    for (final page in _pages) {
      for (final panel in page.panels) {
        for (final element in panel.elements) {
          if (element.type == 'image' && element.src.startsWith('http')) {
            cover = element.src;
            break;
          }
        }
      }
    }
    final res = await BackendApi.instance.call('comics.save', {
      if (widget.comicId != null) 'comicId': widget.comicId,
      'title': _title.text.trim(),
      'pages': ComicPageData.listToJson(_pages),
      'coverUrl': cover,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res == null) {
      await _saveDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Publishing needs the BookNest cloud. Your comic is safe as a '
              'draft on this device — try again when connected.')));
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Comic published ✓')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Anime Studio',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _saving || _uploading ? null : _publish,
            child: _saving || _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: BookNestColors.cyan))
                : const Text('Publish',
                    style: TextStyle(
                        color: BookNestColors.cyan,
                        fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: _uploading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: BookNestColors.cyan),
                  SizedBox(height: 12),
                  Text('Uploading your art…'),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: TextField(
                    controller: _title,
                    onChanged: (_) => _saveDraft(),
                    decoration: InputDecoration(
                      hintText: 'Comic title',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                // page navigation + grid choice
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _page > 0
                            ? () => setState(() => _page -= 1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('Page ${_page + 1} / ${_pages.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: _page < _pages.length - 1
                            ? () => setState(() => _page += 1)
                            : () => setState(() {
                                  _pages = [
                                    ..._pages,
                                    ComicPageData(
                                        pageNumber: _pages.length + 1,
                                        panels:
                                            panelsForGrid(_grid, tag: 'n')),
                                  ];
                                  _page += 1;
                                }),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Panel grid',
                        onSelected: (g) => setState(() {
                          _grid = g;
                          _pages[_page] = _pages[_page]
                              .withPanels(panelsForGrid(g, tag: 'p'));
                          _saveDraft();
                        }),
                        itemBuilder: (context) => [
                          for (final name in kComicGrids.keys)
                            PopupMenuItem(value: name, child: Text(name)),
                        ],
                        child: GlassPanel(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          radius: 12,
                          child: Row(
                            children: [
                              const Icon(Icons.grid_view_rounded,
                                  size: 16, color: BookNestColors.cyan),
                              const SizedBox(width: 6),
                              Text(_grid,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: ComicCanvasWidget(
                      key: ValueKey(
                          'canvas-$_page-${_pages[_page].panels.length}-$_grid'),
                      page: _pages[_page],
                      editMode: true,
                      onPanelsChanged: (panels) {
                        _pages[_page] = _pages[_page].withPanels(panels);
                        _saveDraft();
                      },
                      addArt: _pickAndUpload,
                      editLettering: _editLettering,
                    ),
                  ),
                ),
                if (_pages[_page]
                    .panels
                    .any((p) => p.elements.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: _addArtToFirstFilled,
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18, color: BookNestColors.cyan),
                          label: const Text('Add art',
                              style: TextStyle(
                                  color: BookNestColors.cyan,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: _addLetteringToFirstPanel,
                          icon: const Icon(Icons.chat_bubble_outline_rounded,
                              size: 18, color: BookNestColors.cyan),
                          label: const Text('Add lettering',
                              style: TextStyle(
                                  color: BookNestColors.cyan,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _addArtToFirstFilled() async {
    final panel = _pages[_page].panels
        .firstWhere((p) => p.elements.isNotEmpty);
    final url = await _pickAndUpload(panel);
    if (url == null || url.isEmpty || !mounted) return;
    _insertIntoPanel(panel.id,
        ComicElementData(
          id: 'e${DateTime.now().microsecondsSinceEpoch % 100000000}',
          type: 'image',
          src: url,
          x: 0.5,
          y: 0.55,
          width: 0.72,
        ));
  }

  Future<void> _addLetteringToFirstPanel() async {
    final el = await _editLettering(ComicElementData(
      id: 'e${DateTime.now().microsecondsSinceEpoch % 100000000}',
      type: 'speech_bubble',
      style: 'roundedBox',
      text: 'Say something…',
      x: 0.5,
      y: 0.3,
      width: 0.5,
      anchorX: 0.5,
      anchorY: 0.58,
    ));
    if (el == null || el.text.trim().isEmpty || !mounted) return;
    _insertIntoPanel(_pages[_page].panels.first.id, el);
  }

  void _insertIntoPanel(String panelId, ComicElementData element) {
    final panels = _pages[_page].panels.map((p) {
      if (p.id != panelId) return p;
      return p.withElements([...p.elements, element]);
    }).toList();
    setState(() {
      _pages[_page] = _pages[_page].withPanels(panels);
    });
    _saveDraft();
  }
}
