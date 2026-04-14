// MangaGeko (mgeko.cc) - Uses AJAX data API

import 'package:foxlations/bridge_lib.dart';

class MangaGeko extends MProvider {
  MangaGeko({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/browse-comics/data/?page=$page&sort=popular_weekly';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/browse-comics/data/?page=$page&sort=latest';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/browse-comics/data/?page=$page&q=$q';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    final titleEl = doc.selectFirst('h1, div.manga-title h1, span.manga-title');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Cover
    final imgEl = doc.selectFirst('div.manga-poster img, div.manga-cover img, img.manga-cover');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Author
    final authorEl = doc.selectFirst('div.author a, span.author, a[href*=author]');
    if (authorEl != null) manga.author = authorEl.text.trim();

    // Description
    final descEl = doc.selectFirst('div.description p, div.manga-summary p, div.summary-content, p.description');
    if (descEl != null) manga.description = descEl.text.trim();

    // Genres
    final genreEls = doc.select('div.genres a, div.genre a, span.genre a, a.genre-tag');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Status
    final statusEl = doc.selectFirst('div.status span, span.status, div.manga-status');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
    }

    // Chapters — fetch from /all-chapters/ page for complete list
    final chapters = <MChapter>[];
    final mangaPath = url.startsWith('http')
        ? url.replaceAll(baseUrl, '')
        : url;
    final cleanPath = mangaPath.endsWith('/') ? mangaPath : '$mangaPath/';
    final allChaptersUrl = '$baseUrl${cleanPath}all-chapters/';

    try {
      final chRes = await client.get(allChaptersUrl, headers: {'Referer': '$baseUrl/'});
      final chDoc = Document(chRes.body);
      final chEls = chDoc.select('a[href*="/reader/"]');
      final seen = <String>{};
      for (final el in chEls) {
        final href = el.attr('href');
        if (href == null || seen.contains(href)) continue;
        seen.add(href);
        final ch = MChapter();
        ch.url = href.startsWith('http') ? href : '$baseUrl$href';
        ch.name = el.text.trim();
        if (ch.name == null || ch.name!.isEmpty) {
          // Extract chapter number from URL
          final numMatch = RegExp(r'chapter-(\d+)').firstMatch(href);
          ch.name = numMatch != null ? 'Chapter ${numMatch.group(1)}' : href.split('/').last;
        }
        if (ch.url != null && ch.name!.isNotEmpty) chapters.add(ch);
      }
    } catch (_) {}

    // Fallback: chapters from main detail page
    if (chapters.isEmpty) {
      final chEls = doc.select('a[href*="/reader/"]');
      for (final el in chEls) {
        final ch = MChapter();
        ch.url = el.attr('href');
        if (ch.url != null && !ch.url!.startsWith('http')) {
          ch.url = '$baseUrl${ch.url}';
        }
        ch.name = el.text.trim();
        if (ch.url != null && ch.name != null && ch.name!.isNotEmpty) chapters.add(ch);
      }
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final pages = <String>[];

    // Images have id="image-N" with src pointing to CDN
    var imgEls = doc.select('img[id^=image-]');
    // Fallback: any img in content area
    if (imgEls.isEmpty) imgEls = doc.select('div.page-in img, div.content-wrap img, div.read-content img');
    for (final img in imgEls) {
      final src = img.getSrc();
      if (src != null && src.trim().isNotEmpty && !src.contains('loading') && !src.startsWith('data:')) {
        pages.add(src.trim());
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseList(String body) {
    final mangaList = <MManga>[];

    // API returns JSON with results_html containing comic-card articles
    // Extract page/num_pages for hasNextPage
    int page = 1;
    int numPages = 1;
    final pageMatch = RegExp(r'"page"\s*:\s*(\d+)').firstMatch(body);
    final numPagesMatch = RegExp(r'"num_pages"\s*:\s*(\d+)').firstMatch(body);
    if (pageMatch != null) page = int.tryParse(pageMatch.group(1)!) ?? 1;
    if (numPagesMatch != null) numPages = int.tryParse(numPagesMatch.group(1)!) ?? 1;

    // Extract the HTML from the JSON response
    String html = body;
    final htmlMatch = RegExp(r'"results_html"\s*:\s*"(.*)"', dotAll: true).firstMatch(body);
    if (htmlMatch != null) {
      // Unescape the JSON string
      html = htmlMatch.group(1)!
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\/', '/');
    }

    final doc = Document(html);
    final elements = doc.select('article.comic-card');

    for (final el in elements) {
      final manga = MManga();

      // Link and image from cover section
      final coverLink = el.selectFirst('div.comic-card__cover a');
      if (coverLink != null) {
        manga.link = coverLink.attr('href');
        if (manga.link != null && !manga.link!.startsWith('http')) {
          manga.link = '$baseUrl${manga.link}';
        }
      }
      final imgEl = el.selectFirst('img');
      if (imgEl != null) {
        manga.imageUrl = imgEl.getSrc();
        // Use alt text as title fallback
        if (imgEl.attr('alt') != null) manga.name = imgEl.attr('alt');
      }

      // Title from h3
      final titleEl = el.selectFirst('h3.comic-card__title a');
      if (titleEl != null) manga.name = titleEl.text.trim();

      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) {
        mangaList.add(manga);
      }
    }

    return MPages(mangaList, page < numPages);
  }
}

MangaGeko main(MSource source) {
  return MangaGeko(source: source);
}
