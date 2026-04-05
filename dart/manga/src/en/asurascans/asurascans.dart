// Asura Scans - REST API source
// API at https://api.asurascans.com/api/

import 'package:mangayomi/bridge_lib.dart';

class AsuraScans extends MProvider {
  AsuraScans({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get apiBase => 'https://api.asurascans.com';

  @override
  Future<MPages> getPopular(int page) async {
    final offset = (page - 1) * 20;
    final url = '$apiBase/api/series?sort=rating&order=desc&offset=$offset&limit=20';
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

    // Parse series metadata from JSON
    final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(body);
    if (titleMatch != null) manga.name = titleMatch.group(1)!.replaceAll(r'\"', '"');

    final descMatch = RegExp(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(body);
    if (descMatch != null) manga.description = descMatch.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');

    final coverMatch = RegExp(r'"cover"\s*:\s*"([^"]*)"').firstMatch(body);
    if (coverMatch != null) {
      final cover = coverMatch.group(1)!;
      manga.imageUrl = cover.startsWith('http') ? cover : '$apiBase$cover';
    }

    final authorMatch = RegExp(r'"author"\s*:\s*"([^"]*)"').firstMatch(body);
    if (authorMatch != null) manga.author = authorMatch.group(1);

    final statusMatch = RegExp(r'"status"\s*:\s*"([^"]*)"').firstMatch(body);
    if (statusMatch != null) {
      final s = statusMatch.group(1)!.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
      else if (s.contains('hiatus')) { manga.status = 2; }
    }

    // Genres
    final genreMatches = RegExp(r'"genre"\s*:\s*"([^"]*)"').allMatches(body);
    if (genreMatches.isNotEmpty) {
      manga.genre = genreMatches.map((m) => m.group(1)!).toList();
    }
    // Also try "name" in genres array
    if (manga.genre == null || manga.genre!.isEmpty) {
      final nameInGenres = RegExp(r'"genres"\s*:\s*\[.*?\]', dotAll: true).firstMatch(body);
      if (nameInGenres != null) {
        final names = RegExp(r'"name"\s*:\s*"([^"]*)"').allMatches(nameInGenres.group(0)!);
        if (names.isNotEmpty) {
          manga.genre = names.map((m) => m.group(1)!).toList();
        }
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
      // Parse individual chapter objects
      final objPattern = RegExp(r'\{[^{}]*"number"[^{}]*"slug"[^{}]*\}', dotAll: true);
      for (final obj in objPattern.allMatches(chBody)) {
        final str = obj.group(0)!;
        final numMatch = RegExp(r'"number"\s*:\s*(\d+)').firstMatch(str);
        final slugMatch = RegExp(r'"slug"\s*:\s*"([^"]*)"').firstMatch(str);
        final dateMatch = RegExp(r'"published_at"\s*:\s*"([^"]*)"').firstMatch(str);
        final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(str);

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

    // API returns {"data":[{series},{series},...]}
    // Each series has: title, slug, cover, public_url, latest_chapters (nested)
    // We need to match top-level series fields, not nested chapter fields
    // Split by "public_url" which only appears in series objects
    final seriesPattern = RegExp(
      r'"slug"\s*:\s*"([^"]*)".*?"title"\s*:\s*"((?:[^"\\]|\\.)*)".*?"cover"\s*:\s*"([^"]*)".*?"public_url"\s*:\s*"([^"]*)"',
      dotAll: true,
    );

    for (final m in seriesPattern.allMatches(body)) {
      final manga = MManga();
      manga.name = m.group(2)!.replaceAll(r'\"', '"');
      final pubUrl = m.group(4)!;
      manga.link = '$baseUrl$pubUrl';
      manga.imageUrl = m.group(3)!;
      mangaList.add(manga);
    }

    return MPages(mangaList, mangaList.length >= 20);
  }
}

AsuraScans main(MSource source) {
  return AsuraScans(source: source);
}
