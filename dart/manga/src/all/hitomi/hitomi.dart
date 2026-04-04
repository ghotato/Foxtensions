// Hitomi.la - Gallery site with custom JS/nozomi API

import 'package:mangayomi/bridge_lib.dart';

class Hitomi extends MProvider {
  Hitomi({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get ltnUrl => 'https://ltn.hitomi.la';

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/index-all.html';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseGalleryList(Document(res.body), page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/index-all.html';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseGalleryList(Document(res.body), page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    // Hitomi search uses tag-based URLs
    final q = query.toLowerCase().replaceAll(' ', '_');
    final url = '$baseUrl/search.html?$q';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseGalleryList(Document(res.body), page);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    final titleEl = doc.selectFirst('h1 a, div.gallery h1');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Cover
    final imgEl = doc.selectFirst('div.cover img, picture img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Artists
    final artistEls = doc.select('div.artist-list a, h2 a');
    if (artistEls.isNotEmpty) {
      manga.author = artistEls.map((e) => e.text.trim()).join(', ');
    }

    // Tags
    final tagEls = doc.select('td.relatedtaglinks a, ul.tags li a, span.tags a');
    if (tagEls.isNotEmpty) {
      manga.genre = tagEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Language
    final langEl = doc.selectFirst('td:contains(Language) + td a, table.dj-desc tr:contains(Language) a');
    if (langEl != null) manga.description = 'Language: ${langEl.text.trim()}';

    // Single chapter = the gallery itself
    final ch = MChapter();
    ch.name = manga.name ?? 'Gallery';
    ch.url = url;
    manga.chapters = [ch];

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final pages = <String>[];

    // Try to get gallery JS data
    final galleryId = RegExp(r'(\d+)\.html').firstMatch(fullUrl)?.group(1);
    if (galleryId == null) return pages;

    try {
      // Fetch gallery JS
      final jsUrl = '$ltnUrl/galleries/$galleryId.js';
      final jsRes = await client.get(jsUrl, headers: {'Referer': '$baseUrl/'});
      final body = jsRes.body;

      // Extract image filenames from the JS
      // Format: var galleryinfo = { ... "files": [{"name":"001.jpg","hash":"abc...","width":...}, ...] }
      final filesMatch = RegExp(r'"files"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
      if (filesMatch != null) {
        final nameMatches = RegExp(r'"name"\s*:\s*"([^"]+)"').allMatches(filesMatch.group(1)!);
        final hashMatches = RegExp(r'"hash"\s*:\s*"([^"]+)"').allMatches(filesMatch.group(1)!);

        final names = nameMatches.map((m) => m.group(1)!).toList();
        final hashes = hashMatches.map((m) => m.group(1)!).toList();

        for (int i = 0; i < names.length && i < hashes.length; i++) {
          final hash = hashes[i];
          final name = names[i];
          // Construct image URL using Hitomi's CDN pattern
          // The subdomain is calculated from the hash
          final subdomain = _getSubdomain(hash);
          final hashDir = hash.substring(hash.length - 1);
          final hashDir2 = hash.substring(hash.length - 3, hash.length - 1);
          final ext = name.split('.').last;
          pages.add('https://${subdomain}a.hitomi.la/webp/$hashDir2/$hashDir/$hash.$ext');
        }
      }
    } catch (_) {}

    // Fallback: parse HTML reader page
    if (pages.isEmpty) {
      final readerUrl = fullUrl.replaceFirst('.html', '.js');
      try {
        final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
        final doc = Document(res.body);
        final imgEls = doc.select('div.img-url, img');
        for (final img in imgEls) {
          final src = img.getSrc();
          if (src != null && src.isNotEmpty) pages.add(src);
        }
      } catch (_) {}
    }

    return pages;
  }

  String _getSubdomain(String hash) {
    // Hitomi uses hash-based subdomain routing
    // This changes periodically - simplified version
    final lastChar = hash.codeUnitAt(hash.length - 1);
    final num = lastChar % 3;
    return String.fromCharCode('a'.codeUnitAt(0) + num);
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseGalleryList(Document doc, int page) {
    final mangaList = <MManga>[];

    final elements = doc.select('div.gallery-content div.dj-content a, div.gallery a');
    // Simple pagination: take 25 items per page
    final start = (page - 1) * 25;
    final end = start + 25;

    for (int i = 0; i < elements.length; i++) {
      if (i < start) continue;
      if (i >= end) break;

      final el = elements[i];
      final manga = MManga();
      manga.link = el.attr('href');
      if (manga.link != null && !manga.link!.startsWith('http')) {
        manga.link = '$baseUrl${manga.link}';
      }
      final titleEl = el.selectFirst('div.dj-desc h1, span.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      if (manga.name == null || manga.name!.isEmpty) manga.name = el.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    return MPages(mangaList, end < elements.length);
  }
}

Hitomi main(MSource source) {
  return Hitomi(source: source);
}
