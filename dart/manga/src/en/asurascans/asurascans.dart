// Asura Scans - REST API source
// API at https://api.asurascans.com/api/

import 'package:foxlations/bridge_lib.dart';

class AsuraScans extends MProvider {
  AsuraScans({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get apiBase => 'https://api.asurascans.com';

  @override
  Future<MPages> getPopular(int page) async {
    final offset = (page - 1) * 20;
    final url = '$apiBase/api/series?sort=popular&order=desc&offset=$offset&limit=20';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseSeriesList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final offset = (page - 1) * 20;
    final url = '$apiBase/api/series?sort=latest&order=desc&offset=$offset&limit=20';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseSeriesList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final offset = (page - 1) * 20;
    final q = Uri.encodeComponent(query);
    final url = '$apiBase/api/series?search=$q&offset=$offset&limit=20&sort=rating&order=desc';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseSeriesList(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    // url is like /comics/slug-hash or https://asurascans.com/comics/slug-hash
    var path = url.replaceAll(baseUrl, '').replaceAll('/comics/', '');
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);
    // Remove the hash suffix (e.g. -26f76d6d)
    final slug = path.replaceAll(RegExp(r'-[a-f0-9]{8}$'), '');

    final apiUrl = '$apiBase/api/series/$slug';
    final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
    final body = res.body;
    final manga = MManga();

    // Extract the "series":{...} block — use ,"series":{ to skip recommended_series
    String seriesJson = body;
    final seriesStart = body.indexOf(',"series":{');
    if (seriesStart >= 0) {
      final afterSeries = body.substring(seriesStart);
      // Find end: either ,"recommended_series" or ,"chapters" or end of object
      var endIdx = afterSeries.indexOf(',"recommended_series"');
      if (endIdx < 0) endIdx = afterSeries.indexOf(',"chapters"');
      if (endIdx < 0) endIdx = afterSeries.length;
      seriesJson = afterSeries.substring(0, endIdx);
    }

    // Parse series metadata
    final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(seriesJson);
    if (titleMatch != null) manga.name = titleMatch.group(1)!.replaceAll(r'\"', '"');

    final descMatch = RegExp(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(seriesJson);
    if (descMatch != null) manga.description = descMatch.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');

    final coverMatch = RegExp(r'"cover"\s*:\s*"([^"]*)"').firstMatch(seriesJson);
    if (coverMatch == null) {
      final coverUrlMatch = RegExp(r'"cover_url"\s*:\s*"([^"]*)"').firstMatch(seriesJson);
      if (coverUrlMatch != null) manga.imageUrl = coverUrlMatch.group(1);
    } else {
      manga.imageUrl = coverMatch.group(1);
    }

    final authorMatch = RegExp(r'"author"\s*:\s*"([^"]*)"').firstMatch(seriesJson);
    if (authorMatch != null) manga.author = authorMatch.group(1);

    final statusMatch = RegExp(r'"status"\s*:\s*"([^"]*)"').firstMatch(seriesJson);
    if (statusMatch != null) {
      final s = statusMatch.group(1)!.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
      else if (s.contains('hiatus')) { manga.status = 2; }
    }

    // Genres from the series object's genres array
    final genresBlock = RegExp(r'"genres"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(seriesJson);
    if (genresBlock != null) {
      final names = RegExp(r'"name"\s*:\s*"([^"]*)"').allMatches(genresBlock.group(1)!);
      if (names.isNotEmpty) {
        manga.genre = names.map((m) => m.group(1)!).toList();
      }
    }

    // Fetch chapters via API (paginated)
    final chapters = <MChapter>[];
    var offset = 0;
    var hasMore = true;
    while (hasMore) {
      final chUrl = '$apiBase/api/series/$slug/chapters?offset=$offset&limit=100';
      final chRes = await client.get(chUrl, headers: {'Referer': '$baseUrl/'});
      final chBody = chRes.body;

      final chPattern = RegExp(
        r'"number"\s*:\s*(\d+).*?"slug"\s*:\s*"([^"]*)".*?"published_at"\s*:\s*"([^"]*)"',
        dotAll: true,
      );

      var found = 0;
      // Split the data array by "id": to get individual chapter entries
      // Each chapter starts with {"id": and contains number, slug, title, published_at
      final chEntries = chBody.split('"series_id":');
      for (final entry in chEntries.skip(1)) {
        final numMatch = RegExp(r'"number"\s*:\s*(\d+)').firstMatch(entry);
        final slugMatch = RegExp(r'"slug"\s*:\s*"([^"]*)"').firstMatch(entry);
        final dateMatch = RegExp(r'"published_at"\s*:\s*"([^"]*)"').firstMatch(entry);
        final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(entry);

        if (numMatch != null && slugMatch != null) {
          final ch = MChapter();
          final number = numMatch.group(1)!;
          final chSlug = slugMatch.group(1)!;
          final title = titleMatch?.group(1) ?? '';
          ch.name = title.isNotEmpty && title != 'null'
              ? 'Chapter $number: $title'
              : 'Chapter $number';
          ch.url = '$baseUrl/comics/$path/$chSlug';
          if (dateMatch != null) ch.dateUpload = dateMatch.group(1);
          chapters.add(ch);
          found++;
        }
      }

      hasMore = found >= 100;
      offset += 100;
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // url: /comics/slug-hash/chapter-N or full URL
    final path = url.replaceAll(baseUrl, '').replaceAll('/comics/', '');
    final parts = path.split('/');
    if (parts.length < 2) return [];

    final seriesSlug = parts[0].replaceAll(RegExp(r'-[a-f0-9]{8}$'), '');
    final chapterSlug = parts[1];

    final apiUrl = '$apiBase/api/series/$seriesSlug/chapters/$chapterSlug';
    final res = await client.get(apiUrl, headers: {'Referer': '$baseUrl/'});
    final body = res.body;
    final pages = <String>[];

    // Extract image URLs from pages array
    final urlPattern = RegExp(r'"(?:url|image_url|page_url|image|src)"\s*:\s*"([^"]*)"');
    for (final m in urlPattern.allMatches(body)) {
      final imgUrl = m.group(1)!.replaceAll(r'\/', '/');
      if (imgUrl.contains('.jpg') || imgUrl.contains('.png') || imgUrl.contains('.webp') || imgUrl.contains('.jpeg')) {
        pages.add(imgUrl);
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseSeriesList(String body) {
    final mangaList = <MManga>[];

    // Parse JSON natively to avoid regex matching nested chapter titles
    final data = jsonDecode(body);
    final series = data['data'];
    if (series is List) {
      for (final s in series) {
        final manga = MManga();
        // Try series_title, name, then title as fallback
        final title = s['series_title'] ?? s['name'] ?? s['title'] ?? 'Unknown';
        manga.name = title.toString();
        final pubUrl = (s['public_url'] ?? '').toString();
        manga.link = pubUrl.startsWith('http') ? pubUrl : '$baseUrl$pubUrl';
        manga.imageUrl = (s['cover'] ?? s['cover_url'] ?? '').toString();
        if (manga.name!.isNotEmpty) {
          mangaList.add(manga);
        }
      }
    }

    return MPages(mangaList, mangaList.length >= 20);
  }
}

AsuraScans main(MSource source) {
  return AsuraScans(source: source);
}
