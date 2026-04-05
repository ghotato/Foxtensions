// Kemono - Content aggregator (Patreon, Fanbox, etc.)
// Based on keiyoushi's implementation
// Uses native JSON utilities for large API responses

import 'package:mangayomi/bridge_lib.dart';

class Kemono extends MProvider {
  Kemono({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get imgCdnUrl => baseUrl.replaceFirst('//', '//img.');

  Map<String, String> get _apiHeaders => {
    'Referer': '$baseUrl/',
    'Accept': 'text/css',
  };

  // Cache parsed creators list (native Dart objects from jsonDecode)
  List<dynamic>? _creatorsCache;

  Future<List<dynamic>> _fetchCreators() async {
    if (_creatorsCache != null) return _creatorsCache!;

    final res = await client.get('$baseUrl/api/v1/creators', headers: _apiHeaders);

    // Parse JSON natively (handles 26MB+ in milliseconds)
    final all = jsonDecode(res.body) as List;

    // Filter out discord entries natively
    _creatorsCache = listExclude(all, 'service', ['discord']);
    return _creatorsCache!;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final creators = await _fetchCreators();
    // Sort by favorited descending (most popular first)
    final sorted = listSort(creators, 'favorited', true);
    return _paginateCreators(sorted, page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final creators = await _fetchCreators();
    // Sort by updated descending (most recent first)
    final sorted = listSort(creators, 'updated', true);
    return _paginateCreators(sorted, page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final creators = await _fetchCreators();
    final filtered = listFilter(creators, 'name', query);
    return _paginateCreators(filtered, page);
  }

  MPages _paginateCreators(List<dynamic> creators, int page) {
    const pageSize = 50;
    final fromIndex = (page - 1) * pageSize;
    final toIndex = fromIndex + pageSize;
    final slice = listSlice(creators, fromIndex, toIndex);

    final mangaList = <MManga>[];
    for (final c in slice) {
      final manga = MManga();
      final id = c['id'].toString();
      final service = c['service'].toString();
      manga.name = (c['name'] ?? 'Unknown').toString();
      manga.link = '/$service/user/$id';
      manga.imageUrl = '$imgCdnUrl/icons/$service/$id';
      mangaList.add(manga);
    }

    return MPages(mangaList, toIndex < creators.length);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final manga = MManga();

    // Fetch posts for this creator (each post with images = a chapter)
    final chapters = <MChapter>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final res = await client.get(
        '$baseUrl/api/v1$url/posts?o=$offset',
        headers: _apiHeaders,
      );
      final posts = jsonDecode(res.body) as List;

      for (final post in posts) {
        if (_postHasImages(post)) {
          final ch = MChapter();
          final title = (post['title'] ?? '').toString();
          ch.name = title.isNotEmpty ? title : 'Post ${post['id']}';
          ch.url = '$url/post/${post['id']}';
          final published = post['published']?.toString() ?? '';
          if (published.isNotEmpty) ch.dateUpload = published;
          chapters.add(ch);
        }
      }

      hasMore = posts.length >= 50;
      offset += 50;
    }

    manga.chapters = chapters;
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // url: /{service}/user/{id}/post/{postId}
    final res = await client.get('$baseUrl/api/v1$url', headers: _apiHeaders);
    final data = jsonDecode(res.body);

    // Response is wrapped: {"post": {...}}
    final post = data['post'] ?? data;
    final pages = <String>[];

    // Extract file
    final file = post['file'];
    if (file != null && file['path'] != null) {
      final path = file['path'].toString();
      if (path.isNotEmpty && _isImagePath(path)) {
        pages.add('$baseUrl/data$path');
      }
    }

    // Extract attachments
    final attachments = post['attachments'];
    if (attachments is List) {
      for (final att in attachments) {
        final path = att['path']?.toString() ?? '';
        if (path.isNotEmpty && _isImagePath(path)) {
          final fullUrl = '$baseUrl/data$path';
          if (!pages.contains(fullUrl)) pages.add(fullUrl);
        }
      }
    }

    return pages;
  }

  bool _isImagePath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'gif' || ext == 'webp';
  }

  bool _postHasImages(dynamic post) {
    final file = post['file'];
    if (file != null) {
      final path = file['path']?.toString() ?? '';
      if (path.isNotEmpty && _isImagePath(path)) return true;
    }
    final attachments = post['attachments'];
    if (attachments is List) {
      for (final att in attachments) {
        final path = att['path']?.toString() ?? '';
        if (path.isNotEmpty && _isImagePath(path)) return true;
      }
    }
    return false;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];
}

Kemono main(MSource source) {
  return Kemono(source: source);
}
