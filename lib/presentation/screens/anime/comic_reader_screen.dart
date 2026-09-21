import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/comic_canvas.dart';

/// Reads a published comic: pages rendered live from their JSON document.
class ComicReaderScreen extends StatefulWidget {
  final String comicId;

  const ComicReaderScreen({super.key, required this.comicId});

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  bool _loading = true;
  bool _offline = false;
  String _title = '';
  String _author = '';
  List<ComicPageData> _pages = [];
  final PageController _pager = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance
        .call('comics.get', {'comicId': widget.comicId});
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _title = res?['comic']?['title']?.toString() ?? 'Comic';
      _author = res?['comic']?['ownerName']?.toString() ?? '';
      _pages = ComicPageData.listFromJson(
          (res?['comic']?['pages'] as List?) ?? const []);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(_title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? const Center(
                  child: Text('The comic shelf needs the BookNest cloud.'))
              : _pages.isEmpty
                  ? const Center(child: Text('This comic has no pages yet.'))
                  : Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            controller: _pager,
                            itemCount: _pages.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.all(14),
                              child: ComicCanvasWidget(
                                  key: ValueKey('read-$i'), page: _pages[i]),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'Page ${(_pager.hasClients ? _pager.page?.round() ?? 0 : 0) + 1} of ${_pages.length}'
                            '${_author.isEmpty ? '' : ' · by $_author'}',
                            style: TextStyle(
                                fontSize: 12, color: theme.hintColor),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
