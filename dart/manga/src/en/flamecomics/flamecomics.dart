// Flame Comics - Custom Source (Next.js JSON API)
// Class-based multisrc framework.

import 'package:foxlations/bridge_lib.dart';

class FlameComics extends MProvider {
  FlameComics({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get cdnUrl => 'https://cdn.flamecomics.xyz';

  String _buildId = '';

  Future<String> _getBuildId() async {
    if (_buildId.isNotEmpty) return _buildId;
    final res = await client.get(baseUrl, headers: {'Referer': '$baseUrl/'});
    final match = RegExp(r'"buildId"\s*:\s*"([^"]+)"').firstMatch(res.body);
    if (match != null) {
      _buildId = match.group(1)!;
    }
    return _buildId;
  }

  String _apiUrl(String path) {
    return '$baseUrl/_next/data/$_buildId/$path';
  }

  @override
  Future<MPages> getPopular(int page) async {
    await _getBuildId();
    if (_buildId.isEmpty) return MPages([], false);

    final url = _apiUrl('browse.json?page=$page');
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseBrowse(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    await _getBuildId();
    if (_buildId.isEmpty) return MPages([], false);

    final url = _apiUrl('index.json');
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseBrowse(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    await _getBuildId();
    if (_buildId.isEmpty) return MPages([], false);

    final q = Uri.encodeComponent(query);
    final url = _apiUrl('browse.json?search=$q&page=$page');
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseBrowse(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    await _getBuildId();
    final manga = MManga();

    final seriesId = url.split('/').where((s) => s.isNotEmpty).last;
    final apiUrl = _apiUrl('series/$seriesId.json');
    final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
    final body = res.body;

    // Title
    var match = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(body);
    if (match != null) manga.name = match.group(1);

    // Description
    match = RegExp(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(body);
    if (match != null) {
      manga.description = match.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
    }

    // Cover
    manga.imageUrl = '$cdnUrl/uploads/images/series/$seriesId/thumbnail.png';

    // Author
    match = RegExp(r'"author"\s*:\s*\["([^"]*)"').firstMatch(body);
    if (match != null) manga.author = match.group(1);

    // Status
    match = RegExp(r'"status"\s*:\s*"([^"]*)"').firstMatch(body);
    if (match != null) {
      final s = match.group(1)!.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
      else if (s.contains('hiatus')) { manga.status = 2; }
    }

    // Genres/categories
    final catMatches = RegExp(r'"categories"\s*:\s*\[(.*?)\]').firstMatch(body);
    if (catMatches != null) {
      final cats = RegExp(r'"([^"]+)"').allMatches(catMatches.group(1)!);
      manga.genre = cats.map((m) => m.group(1)!).toList();
    }

    // Chapters
    final chapters = <MChapter>[];
    final chaptersArrayMatch = RegExp(r'"chapters"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
    if (chaptersArrayMatch != null) {
      final chaptersJson = chaptersArrayMatch.group(1)!;
      final chapterObjects = RegExp(r'\{[^}]+\}').allMatches(chaptersJson);
      for (final obj in chapterObjects) {
        final chStr = obj.group(0)!;
        final ch = MChapter();

        final tokenMatch = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(chStr);
        final numberMatch = RegExp(r'"number"\s*:\s*([\d.]+)').firstMatch(chStr);
        final titleMatch = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(chStr);
        final dateMatch = RegExp(r'"created_at"\s*:\s*"([^"]*)"').firstMatch(chStr);

        if (tokenMatch != null) {
          final token = tokenMatch.group(1)!;
          final number = numberMatch?.group(1) ?? '';
          final title = titleMatch?.group(1) ?? '';

          ch.url = '$baseUrl/series/$seriesId/$token';
          ch.name = title.isNotEmpty ? 'Chapter $number: $title' : 'Chapter $number';
          if (dateMatch != null) ch.dateUpload = dateMatch.group(1);
          chapters.add(ch);
        }
      }
    }

    manga.chapters = chapters;
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    await _getBuildId();
    final pages = <String>[];

    final parts = url.replaceAll(baseUrl, '').split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 3) return pages;
    final seriesId = parts[1];
    final token = parts[2];

    final apiUrl = _apiUrl('series/$seriesId/$token.json');
    final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
    final body = res.body;

    // Extract image URLs
    final urlPattern = RegExp(r'"(https?://[^"]*(?:\.jpg|\.jpeg|\.png|\.webp|\.gif)[^"]*)"', caseSensitive: false);
    for (final m in urlPattern.allMatches(body)) {
      final imgUrl = m.group(1)!;
      if (!imgUrl.contains('logo') && !imgUrl.contains('icon') && !imgUrl.contains('avatar')) {
        pages.add(imgUrl);
      }
    }

    // Fallback: relative paths
    if (pages.isEmpty) {
      final pathPattern = RegExp(r'"(?:url|image|src|path)"\s*:\s*"([^"]+)"');
      for (final m in pathPattern.allMatches(body)) {
        final path = m.group(1)!;
        if (path.contains('.') && !path.contains('logo')) {
          pages.add(path.startsWith('http') ? path : '$cdnUrl/$path');
        }
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseBrowse(String body) {
    final mangaList = <MManga>[];

    // Match series_id, title, and cover from each series object
    final pattern = RegExp(
      r'"series_id"\s*:\s*(\d+)\s*,\s*"title"\s*:\s*"([^"]*)".*?"cover"\s*:\s*"([^"]*)"',
      dotAll: true,
    );
    for (final m in pattern.allMatches(body)) {
      final seriesId = m.group(1)!;
      final title = m.group(2)!;
      final cover = m.group(3)!;
      final manga = MManga();
      manga.name = title;
      manga.link = '$baseUrl/series/$seriesId';
      manga.imageUrl = cover.startsWith('http')
          ? cover
          : '$cdnUrl/uploads/images/series/$seriesId/$cover';
      mangaList.add(manga);
    }

    return MPages(mangaList, mangaList.length >= 20);
  }
}

FlameComics main(MSource source) {
  return FlameComics(source: source);
}
