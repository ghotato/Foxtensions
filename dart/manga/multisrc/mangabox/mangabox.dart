// MangaBox (Manganato/Mangakakalot/Mangabat) - Multisrc Framework
// Based on Tachiyomi/Keiyoushi MangaBox implementation
// Executed by d4rt interpreter at runtime.

import 'package:foxlations/bridge_lib.dart';

MSource source;

void main(MSource s) {
  source = s;
}

String get baseUrl => source.baseUrl;
String get lang => source.lang;

// Mutable globals set by the service before each call
int _page = 1;
String _query = '';
String _url = '';

bool supportsLatest() => true;

Map<String, String> headers() => {'Referer': baseUrl};
Map<String, String> getHeader(String url) => {'Referer': baseUrl};

// --- Popular / Latest / Search ---

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = baseUrl + '/manga-list/hot-manga?page=' + _page.toString();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = baseUrl + '/manga-list/latest-manga?page=' + _page.toString();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final normalized = _query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  final url = baseUrl + '/search/story/' + normalized + '?page=' + _page.toString();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

// --- Manga Detail ---

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(_url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  // Title
  var titleEl = doc.selectFirst('div.story-info-right h1');
  if (titleEl == null) titleEl = doc.selectFirst('h1, div.manga-info-content h1');
  if (titleEl != null) manga.name = titleEl.text;

  // Cover image — multiple layouts
  var imgEl = doc.selectFirst('span.info-image img');
  if (imgEl == null) imgEl = doc.selectFirst('div.manga-info-pic img');
  if (imgEl == null) imgEl = doc.selectFirst('div.story-info-left img');
  if (imgEl != null) manga.imageUrl = imgEl.getSrc();

  // Description — prioritize contentBox (actual summary), then fallbacks
  var descEl = doc.selectFirst('div#contentBox');
  if (descEl == null) descEl = doc.selectFirst('div#noidungm');
  if (descEl == null) descEl = doc.selectFirst('div#panel-story-info-description');
  if (descEl == null) descEl = doc.selectFirst('div.description');
  if (descEl != null) {
    var desc = descEl.text.trim();
    // Strip common summary prefixes like "Manga Name summary:"
    final summaryIdx = desc.indexOf('summary:');
    if (summaryIdx >= 0 && summaryIdx < 100) {
      desc = desc.substring(summaryIdx + 'summary:'.length).trim();
    }
    // Remove trailing site attribution
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

  // Info from list layout (older manganato / natomanga)
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

  // Genres fallback from genre-list div
  if (manga.genre == null) {
    final genreLinks = doc.select('div.genre-list a, div.genres-content a');
    if (genreLinks.isNotEmpty) {
      manga.genre = genreLinks.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }
  }

  // Chapters — try API first, then fallback to HTML
  final chapters = <MChapter>[];
  final slug = _url.split('/').where((s) => s.isNotEmpty).last;
  bool usedApi = false;

  // Try chapters API (newer mangabox sites)
  try {
    final apiUrl = '$baseUrl/api/manga/$slug/chapters?limit=10000&offset=0';
    final apiRes = await client.get(apiUrl, headers: {'Referer': baseUrl});
    if (apiRes.statusCode == 200 && apiRes.body.contains('"chapters"')) {
      // Match: "chapter_name":"Chapter 3862",..."chapter_slug":"chapter-3862"
      // Use .*? instead of [^}]* to handle nested objects between the fields
      final chPattern = RegExp(r'"chapter_name"\s*:\s*"([^"]*)".*?"chapter_slug"\s*:\s*"([^"]*)"', dotAll: true);
      final matches = chPattern.allMatches(apiRes.body);
      // Build manga base URL for chapter links
      final mangaBase = _url.endsWith('/') ? _url : _url + '/';
      for (final m in matches) {
        final ch = MChapter();
        ch.name = m.group(1);
        ch.url = '$mangaBase${m.group(2)}';
        if (ch.url != null) { chapters.add(ch); }
      }
      if (chapters.isNotEmpty) { usedApi = true; }
    }
  } catch (_) {}

  // Fallback: parse chapters from HTML
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

// --- Page List ---

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  final res = await client.get(_url, headers: {'Referer': baseUrl});
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

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

// --- Helpers ---

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  // Try multiple list item selectors (different mangabox site layouts)
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
    // Fallback title from h3
    final titleEl = el.selectFirst('h3 a');
    if (titleEl != null && (manga.name == null || manga.name!.isEmpty)) {
      manga.name = titleEl.text.trim();
    }
    if (manga.name != null && manga.link != null) mangaList.add(manga);
  }

  // Check for pagination links
  var nextPage = doc.selectFirst('a.page-next, a.page-blue.page-last, a.active + a');
  // Fallback: if we got a full page of results, assume there's more
  final hasNext = nextPage != null || mangaList.length >= 20;
  return MPages(list: mangaList, hasNextPage: hasNext);
}
