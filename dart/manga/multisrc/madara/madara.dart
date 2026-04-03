// Madara WordPress Theme - Multisrc Framework
// Based on Tachiyomi/Keiyoushi Madara implementation
// Executed by d4rt interpreter at runtime.

import 'package:foxlations/bridge_lib.dart';

MSource source;

void main(MSource s) {
  source = s;
}

String get baseUrl => source.baseUrl;
String get lang => source.lang;
String get dateFormat => source.dateFormat ?? 'MMMM dd, yyyy';
String get dateFormatLocale => source.dateFormatLocale ?? 'en_us';

// Configurable manga path (some sites use /webtoon/, /comic/, etc)
String get mangaPath => source.additionalParams ?? 'manga';

bool supportsLatest() => true;

Map<String, String> headers() => {'Referer': baseUrl};
Map<String, String> getHeader(String url) => {'Referer': baseUrl};

// --- Popular / Latest / Search ---

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = baseUrl + '/' + mangaPath + '/page/' + page.toString() + '/?m_orderby=views';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = baseUrl + '/' + mangaPath + '/page/' + page.toString() + '/?m_orderby=latest';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final encodedQuery = Uri.encodeComponent(query);
  final url = baseUrl + '/page/' + page.toString() + '/?s=' + encodedQuery + '&post_type=wp-manga';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseSearchResults(Document(res.body));
}

// --- Manga Detail ---

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  // Title
  var titleEl = doc.selectFirst('div.post-title h1');
  if (titleEl == null) titleEl = doc.selectFirst('div.post-title h3');
  if (titleEl == null) titleEl = doc.selectFirst('#manga-title h1');
  if (titleEl != null) manga.name = titleEl.text;

  // Cover image
  var imgEl = doc.selectFirst('div.summary_image img');
  if (imgEl == null) imgEl = doc.selectFirst('div.tab-summary img');
  if (imgEl != null) manga.imageUrl = imgEl.getSrc();

  // Author
  var authorEl = doc.selectFirst('div.author-content > a');
  if (authorEl == null) authorEl = doc.selectFirst('div.manga-authors > a');
  if (authorEl != null) manga.author = authorEl.text.trim();

  // Artist
  final artistEl = doc.selectFirst('div.artist-content > a');
  if (artistEl != null) manga.artist = artistEl.text.trim();

  // Description
  var descEl = doc.selectFirst('div.description-summary div.summary__content');
  if (descEl == null) descEl = doc.selectFirst('div.summary__content');
  if (descEl == null) descEl = doc.selectFirst('div.manga-excerpt');
  if (descEl != null) manga.description = descEl.text;

  // Status
  final statusItems = doc.select('div.post-status div.summary-content');
  if (statusItems.length >= 2) {
    final statusText = statusItems[1].text.toLowerCase();
    if (statusText.contains('ongoing')) { manga.status = 0; }
    else if (statusText.contains('completed')) { manga.status = 1; }
    else if (statusText.contains('hiatus')) { manga.status = 2; }
    else if (statusText.contains('cancel')) { manga.status = 3; }
  }

  // Genres
  final genreEls = doc.select('div.genres-content a');
  if (genreEls.isNotEmpty) {
    manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
  }

  // Chapters — AJAX fetch
  manga.chapters = await _getChapterList(url, res.body);

  return manga;
}

// --- Chapters (AJAX) ---

Future<List<MChapter>> _getChapterList(String mangaUrl, String pageHtml) async {
  final client = Client();

  // Ensure mangaUrl ends with /
  final normalizedUrl = mangaUrl.endsWith('/') ? mangaUrl : '$mangaUrl/';

  String chapterHtml = '';

  // Method 1 (preferred): POST to {mangaUrl}ajax/chapters/
  try {
    final res = await client.post(
      '${normalizedUrl}ajax/chapters/',
      headers: {
        'Referer': mangaUrl,
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: '',
    );
    if (res.statusCode == 200 && res.body.isNotEmpty) {
      chapterHtml = res.body;
    }
  } catch (_) {}

  // Method 2: POST to wp-admin/admin-ajax.php with manga ID
  if (chapterHtml.isEmpty) {
    final doc = Document(pageHtml);
    final holderEl = doc.selectFirst('[id^=manga-chapters-holder]');
    final mangaId = holderEl != null ? holderEl.attr('data-id') : null;

    if (mangaId != null) {
      try {
        final res = await client.post(
          '$baseUrl/wp-admin/admin-ajax.php',
          headers: {
            'Referer': mangaUrl,
            'X-Requested-With': 'XMLHttpRequest',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'action=manga_get_chapters&manga=$mangaId',
        );
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          chapterHtml = res.body;
        }
      } catch (_) {}
    }
  }

  // Method 3: Fallback to chapters already in the page HTML
  if (chapterHtml.isEmpty) {
    chapterHtml = pageHtml;
  }

  return _parseChapters(chapterHtml);
}

List<MChapter> _parseChapters(String html) {
  final doc = Document(html);
  final chapters = <MChapter>[];

  final elements = doc.select('li.wp-manga-chapter');
  for (final el in elements) {
    final chapter = MChapter();
    final linkEl = el.selectFirst('a');
    if (linkEl != null) {
      chapter.name = linkEl.text.trim();
      chapter.url = linkEl.attr('href');
    }
    final dateEl = el.selectFirst('span.chapter-release-date');
    if (dateEl == null) {
      final altDate = el.selectFirst('span.c-new-tag a');
      if (altDate != null) chapter.dateUpload = altDate.text.trim();
    } else {
      chapter.dateUpload = dateEl.text.trim();
    }
    if (chapter.url != null) chapters.add(chapter);
  }

  return chapters;
}

// --- Page List ---

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  // Append ?style=list for single-page chapter view
  final fetchUrl = url.contains('?') ? '$url&style=list' : '$url?style=list';
  final res = await client.get(fetchUrl, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final pages = <String>[];

  // Check for chapter-protector (some Madara sites encrypt images)
  final protector = doc.selectFirst('#chapter-protector-data');
  if (protector != null) {
    // Try to extract from protector data attribute
    final data = protector.attr('data-wpmanga-protect');
    if (data != null && data.isNotEmpty) {
      final urlPattern = RegExp(r'https?://[^\s"<>]+\.(jpg|jpeg|png|gif|webp)', caseSensitive: false);
      final matches = urlPattern.allMatches(data);
      for (final m in matches) {
        pages.add(m.group(0)!);
      }
    }
  }

  // Primary: div.page-break img
  if (pages.isEmpty) {
    final imgElements = doc.select('div.page-break img');
    for (final img in imgElements) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) pages.add(src.trim());
    }
  }

  // Fallback: reading-content img
  if (pages.isEmpty) {
    final imgs = doc.select('div.reading-content img');
    for (final img in imgs) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) pages.add(src.trim());
    }
  }

  // Fallback: gallery items
  if (pages.isEmpty) {
    final galleryImgs = doc.select('li.blocks-gallery-item img');
    for (final img in galleryImgs) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) pages.add(src.trim());
    }
  }

  return pages;
}

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

// --- Helpers ---

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  // Try multiple layouts
  var elements = doc.select('div.page-item-detail');
  if (elements.isEmpty) elements = doc.select('.manga__item');

  for (final el in elements) {
    final manga = MManga();
    final titleEl = el.selectFirst('div.post-title a, h3.h5 a, h3 a');
    if (titleEl != null) {
      manga.name = titleEl.text.trim();
      manga.link = titleEl.attr('href');
    }
    final imgEl = el.selectFirst('img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    if (manga.name != null && manga.link != null) mangaList.add(manga);
  }

  var nextPage = doc.selectFirst('div.nav-previous a, a.nextpostslink, a.last');
  final hasNext = nextPage != null || mangaList.length >= 20;
  return MPages(list: mangaList, hasNextPage: hasNext);
}

MPages _parseSearchResults(Document doc) {
  final mangaList = <MManga>[];

  // Search results use different layout
  var elements = doc.select('div.c-tabs-item__content');
  if (elements.isEmpty) elements = doc.select('div.page-item-detail');

  for (final el in elements) {
    final manga = MManga();
    final titleEl = el.selectFirst('div.post-title a, h3 a');
    if (titleEl != null) {
      manga.name = titleEl.text.trim();
      manga.link = titleEl.attr('href');
    }
    final imgEl = el.selectFirst('img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    if (manga.name != null && manga.link != null) mangaList.add(manga);
  }

  var nextPage = doc.selectFirst('div.nav-previous a, a.nextpostslink');
  final hasNext = nextPage != null || mangaList.length >= 20;
  return MPages(list: mangaList, hasNextPage: hasNext);
}
