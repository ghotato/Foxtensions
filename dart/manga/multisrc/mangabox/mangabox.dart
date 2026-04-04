// MangaBox (Manganato/Mangakakalot/Mangabat) - Multisrc Framework
// Class-based pattern compatible with mangayomi's invoke() system.

import 'package:mangayomi/bridge_lib.dart';

class MangaBox extends MProvider {
  MangaBox({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/manga-list/hot-manga?page=$page';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/manga-list/latest-manga?page=$page';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final normalized = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final url = '$baseUrl/search/story/$normalized?page=$page';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': baseUrl});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    var titleEl = doc.selectFirst('div.story-info-right h1');
    if (titleEl == null) titleEl = doc.selectFirst('h1, div.manga-info-content h1');
    if (titleEl != null) manga.name = titleEl.text;

    // Cover image
    var imgEl = doc.selectFirst('span.info-image img');
    if (imgEl == null) imgEl = doc.selectFirst('div.manga-info-pic img');
    if (imgEl == null) imgEl = doc.selectFirst('div.story-info-left img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Description
    var descEl = doc.selectFirst('div#contentBox');
    if (descEl == null) descEl = doc.selectFirst('div#noidungm');
    if (descEl == null) descEl = doc.selectFirst('div#panel-story-info-description');
    if (descEl == null) descEl = doc.selectFirst('div.description');
    if (descEl != null) {
      var desc = descEl.text.trim();
      final summaryIdx = desc.indexOf('summary:');
      if (summaryIdx >= 0 && summaryIdx < 100) {
        desc = desc.substring(summaryIdx + 'summary:'.length).trim();
      }
      final mangaUpdatesIdx = desc.lastIndexOf('MangaUpdates');
      if (mangaUpdatesIdx > 0) desc = desc.substring(0, mangaUpdatesIdx).trim();
      final mangaBuddyIdx = desc.lastIndexOf('MangaBuddy');
      if (mangaBuddyIdx > 0) desc = desc.substring(0, mangaBuddyIdx).trim();
      manga.description = desc;
    }

    // Info from table layout (newer manganato)
    final tableRows = doc.select('table.variations-tableInfo tr');
    for (final row in tableRows) {
      final label = row.selectFirst('td.table-label, label.info-title');
      final value = row.selectFirst('td.table-value');
      if (label != null && value != null) {
        final labelText = label.text.toLowerCase();
        if (labelText.contains('author')) {
          final a = value.selectFirst('a');
          manga.author = a != null ? a.text.trim() : value.text.trim();
        }
        if (labelText.contains('status')) {
          final s = value.text.toLowerCase();
          if (s.contains('ongoing')) { manga.status = 0; }
          else if (s.contains('completed')) { manga.status = 1; }
        }
        if (labelText.contains('genre')) {
          manga.genre = value.select('a').map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
        }
      }
    }

    // Info from list layout (older manganato)
    if (manga.author == null) {
      final infoItems = doc.select('ul.manga-info-text li');
      for (final li in infoItems) {
        final text = li.text.toLowerCase();
        if (text.contains('author')) {
          final a = li.selectFirst('a');
          if (a != null) manga.author = a.text.trim();
        }
        if (text.contains('status')) {
          if (text.contains('ongoing')) { manga.status = 0; }
          else if (text.contains('completed')) { manga.status = 1; }
        }
      }
    }

    // Genres fallback
    if (manga.genre == null) {
      final genreLinks = doc.select('div.genre-list a, div.genres-content a');
      if (genreLinks.isNotEmpty) {
        manga.genre = genreLinks.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
      }
    }

    // Chapters — try API first, then fallback to HTML
    final chapters = <MChapter>[];
    final slug = url.split('/').where((s) => s.isNotEmpty).last;
    bool usedApi = false;

    try {
      final apiUrl = '$baseUrl/api/manga/$slug/chapters?limit=10000&offset=0';
      final apiRes = await client.get(apiUrl, headers: {'Referer': baseUrl});
      if (apiRes.statusCode == 200 && apiRes.body.contains('"chapters"')) {
        final chPattern = RegExp(r'"chapter_name"\s*:\s*"([^"]*)".*?"chapter_slug"\s*:\s*"([^"]*)"', dotAll: true);
        final matches = chPattern.allMatches(apiRes.body);
        final mangaBase = url.endsWith('/') ? url : '$url/';
        for (final m in matches) {
          final ch = MChapter();
          ch.name = m.group(1);
          ch.url = '$mangaBase${m.group(2)}';
          if (ch.url != null) { chapters.add(ch); }
        }
        if (chapters.isNotEmpty) { usedApi = true; }
      }
    } catch (_) {}

    if (!usedApi) {
      var chapterEls = doc.select('ul.row-content-chapter li');
      if (chapterEls.isEmpty) { chapterEls = doc.select('div.chapter-list div.row'); }
      if (chapterEls.isEmpty) { chapterEls = doc.select('div.manga-info-chapter div.row'); }

      for (final el in chapterEls) {
        final ch = MChapter();
        final linkEl = el.selectFirst('a');
        if (linkEl != null) {
          ch.name = linkEl.text.trim();
          ch.url = linkEl.attr('href');
        }
        final dateEl = el.selectFirst('span.chapter-time');
        if (dateEl != null) {
          ch.dateUpload = dateEl.text.trim();
        }
        if (ch.url != null) { chapters.add(ch); }
      }
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(url, headers: {'Referer': baseUrl});
    final body = res.body;
    final pages = <String>[];

    // Method 1: Extract from JavaScript arrays (CDN-based)
    final cdnMatch = RegExp(r'var\s+cdns\s*=\s*(\[.*?\])', dotAll: true).firstMatch(body);
    final imagesMatch = RegExp(r'var\s+chapterImages\s*=\s*(\[.*?\])', dotAll: true).firstMatch(body);

    if (cdnMatch != null && imagesMatch != null) {
      final cdnUrls = RegExp(r'"(https?://[^"]+)"').allMatches(cdnMatch.group(1)!);
      final imagePaths = RegExp(r'"([^"]+)"').allMatches(imagesMatch.group(1)!);

      if (cdnUrls.isNotEmpty) {
        final cdn = cdnUrls.first.group(1)!;
        for (final img in imagePaths) {
          final path = img.group(1)!;
          if (path.contains('.') && !path.contains('http')) {
            pages.add('$cdn$path');
          } else if (path.startsWith('http')) {
            pages.add(path);
          }
        }
      }
    }

    // Method 2: Fallback to HTML img tags
    if (pages.isEmpty) {
      final doc = Document(body);
      final imgElements = doc.select('div.container-chapter-reader img');
      if (imgElements.isEmpty) {
        final altImgs = doc.select('div.panel-read-story img');
        for (final img in altImgs) {
          final src = img.getSrc();
          if (src != null && src.isNotEmpty) pages.add(src.trim());
        }
      } else {
        for (final img in imgElements) {
          final src = img.getSrc();
          if (src != null && src.isNotEmpty) pages.add(src.trim());
        }
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseMangaList(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('div.list-comic-item-wrap');
    if (elements.isEmpty) elements = doc.select('div.list-truyen-item-wrap');
    if (elements.isEmpty) elements = doc.select('div.content-genres-item');
    if (elements.isEmpty) elements = doc.select('div.search-story-item');
    if (elements.isEmpty) elements = doc.select('div.story_item');

    for (final el in elements) {
      final manga = MManga();
      final linkEl = el.selectFirst('a');
      if (linkEl != null) {
        manga.link = linkEl.attr('href');
        manga.name = linkEl.attr('title') ?? '';
      }
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      final titleEl = el.selectFirst('h3 a');
      if (titleEl != null && (manga.name == null || manga.name!.isEmpty)) {
        manga.name = titleEl.text.trim();
      }
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    var nextPage = doc.selectFirst('a.page-next, a.page-blue.page-last, a.active + a');
    final hasNext = nextPage != null || mangaList.length >= 20;
    return MPages(mangaList, hasNext);
  }
}

MangaBox main(MSource source) {
  return MangaBox(source: source);
}
