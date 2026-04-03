// Flame Comics - Custom Source
// Uses Next.js JSON API at flamecomics.xyz
// Executed by d4rt interpreter at runtime.

import 'package:foxlations/bridge_lib.dart';

MSource source;

void main(MSource s) {
  source = s;
}

String get baseUrl => source.baseUrl;
String get cdnUrl => 'https://cdn.flamecomics.xyz';

bool supportsLatest() => true;

Map<String, String> headers() => {'Referer': '$baseUrl/'};
Map<String, String> getHeader(String url) => {'Referer': '$baseUrl/'};

String _buildId = '';

// --- Build ID ---
// Flame Comics is a Next.js site; we need the buildId for API calls.

Future<String> _getBuildId() async {
  if (_buildId.isNotEmpty) return _buildId;
  final client = Client();
  final res = await client.get(baseUrl, headers: {'Referer': '$baseUrl/'});
  print('[FlameComics] getBuildId response length: ${res.body.length}, status: ${res.statusCode}');
  print('[FlameComics] body contains __NEXT_DATA__: ${res.body.contains('__NEXT_DATA__')}');
  // Extract buildId from __NEXT_DATA__ JSON
  final match = RegExp(r'"buildId"\s*:\s*"([^"]+)"').firstMatch(res.body);
  if (match != null) {
    _buildId = match.group(1)!;
    print('[FlameComics] Found buildId: $_buildId');
  } else {
    print('[FlameComics] buildId NOT found in response');
    // Show first 500 chars for debugging
    final preview = res.body.length > 500 ? res.body.substring(0, 500) : res.body;
    print('[FlameComics] Body preview: $preview');
  }
  return _buildId;
}

String _apiUrl(String path) {
  return '$baseUrl/_next/data/$_buildId/$path';
}

// --- Popular ---

Future<MPages> getPopular(int page) async {
  await _getBuildId();
  if (_buildId.isEmpty) return MPages(list: <MManga>[], hasNextPage: false);

  final client = Client();
  final url = _apiUrl('browse.json?page=' + page.toString());
  final res = await client.get(url, headers: {'Referer': baseUrl + '/'});
  return _parseBrowse(res.body);
}

// --- Latest Updates ---

Future<MPages> getLatestUpdates(int page) async {
  await _getBuildId();
  if (_buildId.isEmpty) return MPages(list: <MManga>[], hasNextPage: false);

  final client = Client();
  final url = _apiUrl('index.json');
  final res = await client.get(url, headers: {'Referer': baseUrl + '/'});
  return _parseIndex(res.body);
}

// --- Search ---

Future<MPages> search(String query, int page, FilterList filterList) async {
  await _getBuildId();
  if (_buildId.isEmpty) return MPages(list: <MManga>[], hasNextPage: false);

  final client = Client();
  final q = Uri.encodeComponent(query);
  final url = _apiUrl('browse.json?search=' + q + '&page=' + page.toString());
  final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
  return _parseBrowse(res.body);
}

// --- Manga Detail ---

Future<MManga> getDetail(String url) async {
  await _getBuildId();
  final client = Client();
  final manga = MManga();

  // url is like https://flamecomics.xyz/series/123
  // We need the series ID
  final seriesId = url.split('/').where((s) => s.isNotEmpty).last;

  final apiUrl = _apiUrl('series/$seriesId.json');
  final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
  final body = res.body;

  // Parse title
  var match = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(body);
  if (match != null) manga.name = match.group(1);

  // Parse description
  match = RegExp(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(body);
  if (match != null) {
    manga.description = match.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
  }

  // Parse cover
  match = RegExp(r'"cover"\s*:\s*"([^"]*)"').firstMatch(body);
  if (match != null) {
    final cover = match.group(1)!;
    manga.imageUrl = cover.startsWith('http') ? cover : '$cdnUrl/uploads/images/series/$cover';
  }

  // Parse author
  match = RegExp(r'"author"\s*:\s*"([^"]*)"').firstMatch(body);
  if (match != null) manga.author = match.group(1);

  // Parse status
  match = RegExp(r'"status"\s*:\s*"([^"]*)"').firstMatch(body);
  if (match != null) {
    final s = match.group(1)!.toLowerCase();
    if (s.contains('ongoing')) { manga.status = 0; }
    else if (s.contains('completed')) { manga.status = 1; }
    else if (s.contains('hiatus')) { manga.status = 2; }
  }

  // Parse genres/tags
  final genreMatches = RegExp(r'"genre"\s*:\s*"([^"]*)"').allMatches(body);
  if (genreMatches.isNotEmpty) {
    manga.genre = genreMatches.map((m) => m.group(1)!).toList();
  }
  // Also try tags array
  if (manga.genre == null || manga.genre!.isEmpty) {
    final tagMatches = RegExp(r'"tag"\s*:\s*"([^"]*)"').allMatches(body);
    if (tagMatches.isNotEmpty) {
      manga.genre = tagMatches.map((m) => m.group(1)!).toList();
    }
  }

  // Parse chapters
  final chapters = <MChapter>[];
  // Match chapter entries - they have token and number/title
  final chapterPattern = RegExp(
    r'"token"\s*:\s*"([^"]+)".*?"number"\s*:\s*([\d.]+)(?:.*?"title"\s*:\s*"([^"]*)")?',
    dotAll: true,
  );

  // First, find the chapters array
  final chaptersArrayMatch = RegExp(r'"chapters"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
  if (chaptersArrayMatch != null) {
    final chaptersJson = chaptersArrayMatch.group(1)!;
    // Parse individual chapter objects
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

        if (dateMatch != null) {
          ch.dateUpload = dateMatch.group(1);
        }

        chapters.add(ch);
      }
    }
  }

  manga.chapters = chapters;
  return manga;
}

// --- Page List ---

Future<List<dynamic>> getPageList(String url) async {
  await _getBuildId();
  final client = Client();
  final pages = <String>[];

  // url is like https://flamecomics.xyz/series/123/token
  final parts = url.replaceAll(baseUrl, '').split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 3) return pages;
  final seriesId = parts[1];
  final token = parts[2];

  final apiUrl = _apiUrl('series/$seriesId/$token.json');
  final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
  final body = res.body;

  // Extract image URLs from the response
  // Images are typically in a "images" or "pages" array
  final urlPattern = RegExp(r'"(https?://[^"]*(?:\.jpg|\.jpeg|\.png|\.webp|\.gif)[^"]*)"', caseSensitive: false);
  for (final m in urlPattern.allMatches(body)) {
    final imgUrl = m.group(1)!;
    if (!imgUrl.contains('logo') && !imgUrl.contains('icon') && !imgUrl.contains('avatar')) {
      pages.add(imgUrl);
    }
  }

  // If no full URLs, look for relative paths
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

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

// --- Helpers ---

MPages _parseBrowse(String body) {
  final mangaList = <MManga>[];

  // JSON structure: {"pageProps":{"series":[{"series_id":99,"title":"...","cover":"thumbnail.png",...}]}}
  // Match each series object by finding series_id and title pairs
  final pattern = RegExp(r'"series_id"\s*:\s*(\d+)\s*,\s*"title"\s*:\s*"([^"]*)"', dotAll: true);

  for (final m in pattern.allMatches(body)) {
    final seriesId = m.group(1)!;
    final title = m.group(2)!;
    final manga = MManga();
    manga.name = title;
    manga.link = '$baseUrl/series/$seriesId';
    manga.imageUrl = '$cdnUrl/uploads/images/series/$seriesId/thumbnail.png';
    mangaList.add(manga);
  }

  return MPages(list: mangaList, hasNextPage: mangaList.length >= 20);
}

MPages _parseIndex(String body) {
  return _parseBrowse(body);
}
