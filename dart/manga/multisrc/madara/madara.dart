// Madara WordPress Theme - Multisrc Framework
// Class-based multisrc framework.

import 'package:foxlations/bridge_lib.dart';

class Madara extends MProvider {
  Madara({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get mangaPath => source.additionalParams ?? 'manga';

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/$mangaPath/page/$page/?m_orderby=views';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/$mangaPath/page/$page/?m_orderby=latest';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final encodedQuery = Uri.encodeComponent(query);
    final url = '$baseUrl/page/$page/?s=$encodedQuery&post_type=wp-manga';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseSearchResults(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': baseUrl});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    var titleEl = doc.selectFirst('div.post-title h1');
    if (titleEl == null) titleEl = doc.selectFirst('div.post-title h3');
    if (titleEl == null) titleEl = doc.selectFirst('#manga-title h1');
    if (titleEl != null) manga.name = titleEl.text;

    // Cover
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

    // Chapters — AJAX fetch (inlined to avoid d4rt async nesting issues)
    final normalizedUrl = url.endsWith('/') ? url : '$url/';
    String chapterHtml = '';

    try {
      final chRes = await client.post(
        '${normalizedUrl}ajax/chapters/',
        headers: {
          'Referer': url,
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: '',
      );
      if (chRes.statusCode == 200 && chRes.body.isNotEmpty) {
        chapterHtml = chRes.body;
      }
    } catch (_) {}

    if (chapterHtml.isEmpty) {
      chapterHtml = res.body;
    }

    final chDoc = Document(chapterHtml);
    final chapters = <MChapter>[];
    final chElements = chDoc.select('li.wp-manga-chapter');
    for (final el in chElements) {
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
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fetchUrl = url.contains('?') ? '$url&style=list' : '$url?style=list';
    final res = await client.get(fetchUrl, headers: {'Referer': baseUrl});
    final doc = Document(res.body);
    final pages = <String>[];

    // Check for chapter-protector
    final protector = doc.selectFirst('#chapter-protector-data');
    if (protector != null) {
      final data = protector.attr('data-wpmanga-protect');
      if (data != null && data.isNotEmpty) {
        final urlPattern = RegExp(r'https?://[^\s"<>]+\.(jpg|jpeg|png|gif|webp)', caseSensitive: false);
        final matches = urlPattern.allMatches(data);
        for (final m in matches) {
          pages.add(m.group(0)!);
        }
      }
    }

    // Primary: chapter images
    if (pages.isEmpty) {
      var imgElements = doc.select('div.page-break img');
      if (imgElements.isEmpty) imgElements = doc.select('img.wp-manga-chapter-img');
      if (imgElements.isEmpty) imgElements = doc.select('div.reading-content img');
      for (final img in imgElements) {
        final src = img.getSrc();
        if (src != null && src.trim().isNotEmpty) pages.add(src.trim());
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

    var elements = doc.select('div.page-item-detail');
    if (elements.isEmpty) elements = doc.select('div.page-listing-item');
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
    return MPages(mangaList, hasNext);
  }

  MPages _parseSearchResults(Document doc) {
    final mangaList = <MManga>[];

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
    return MPages(mangaList, hasNext);
  }
}

Madara main(MSource source) {
  return Madara(source: source);
}
