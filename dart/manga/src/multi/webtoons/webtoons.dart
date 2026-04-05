// Webtoons.com - Official webtoon platform
// HTML scraping with pagination

import 'package:mangayomi/bridge_lib.dart';

class Webtoons extends MProvider {
  Webtoons({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get lang => source.lang ?? 'en';

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/$lang/ranking/trending';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseRanking(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/$lang/ranking/trending';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseRanking(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/$lang/search?keyword=$q&page=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseSearchResults(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final body = res.body;
    final manga = MManga();

    // Title from og:title or h1.subj
    final ogTitle = doc.selectFirst('meta[property=og:title]');
    if (ogTitle != null) manga.name = ogTitle.attr('content');
    if (manga.name == null || manga.name!.isEmpty) {
      final titleEl = doc.selectFirst('h1.subj');
      if (titleEl != null) manga.name = titleEl.text.trim();
    }

    // Cover from og:image
    final ogImage = doc.selectFirst('meta[property=og:image]');
    if (ogImage != null) manga.imageUrl = ogImage.attr('content');

    // Author
    final authorEl = doc.selectFirst('div.author_area a, a.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    // Description from og:description
    final ogDesc = doc.selectFirst('meta[property=og:description]');
    if (ogDesc != null) manga.description = ogDesc.attr('content');

    // Genre
    final genreEl = doc.selectFirst('h2.genre, p.genre');
    if (genreEl != null) {
      manga.genre = [genreEl.text.trim()];
    }

    // Status
    final dayInfo = doc.selectFirst('p.day_info');
    if (dayInfo != null) {
      final s = dayInfo.text.toLowerCase();
      if (s.contains('completed') || s.contains('end')) { manga.status = 1; }
      else { manga.status = 0; }
    }

    // Chapters — paginate through all episode pages
    final chapters = <MChapter>[];

    // Extract title_no from URL for pagination
    final titleNoMatch = RegExp(r'title_no=(\d+)').firstMatch(fullUrl);
    final titleNo = titleNoMatch?.group(1) ?? '';

    // Get base list URL (without page param)
    final listBase = fullUrl.contains('?')
        ? fullUrl.replaceAll(RegExp(r'&page=\d+'), '')
        : fullUrl;

    var page = 1;
    var hasMore = true;
    while (hasMore && page <= 50) {
      final pageUrl = '$listBase&page=$page';
      String pageBody;
      if (page == 1) {
        pageBody = body; // Reuse first page
      } else {
        final pageRes = await client.get(pageUrl, headers: {'Referer': '$baseUrl/'});
        pageBody = pageRes.body;
      }
      final pageDoc = Document(pageBody);
      final episodes = pageDoc.select('li._episodeItem a');

      if (episodes.isEmpty) {
        hasMore = false;
        break;
      }

      for (final el in episodes) {
        final ch = MChapter();
        ch.url = el.attr('href');
        final nameEl = el.selectFirst('span.subj span');
        if (nameEl != null) {
          ch.name = nameEl.text.trim();
        } else {
          final altName = el.selectFirst('span.subj');
          ch.name = altName != null ? altName.text.trim() : 'Episode $page';
        }
        final dateEl = el.selectFirst('span.date');
        if (dateEl != null) ch.dateUpload = dateEl.text.trim();
        if (ch.url != null && ch.name != null) chapters.add(ch);
      }

      hasMore = episodes.length >= 10;
      page++;
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

    // Images use data-url attribute on img._images
    final imgEls = doc.select('img._images');
    for (final img in imgEls) {
      final dataUrl = img.attr('data-url');
      if (dataUrl != null && dataUrl.isNotEmpty) {
        pages.add(dataUrl.trim());
      }
    }

    // Fallback: viewer_img area
    if (pages.isEmpty) {
      final altImgs = doc.select('div.viewer_img img');
      for (final img in altImgs) {
        final src = img.getSrc();
        if (src != null && src.isNotEmpty && !src.contains('loading')) {
          pages.add(src.trim());
        }
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseRanking(Document doc) {
    final mangaList = <MManga>[];

    final elements = doc.select('ul.webtoon_list li a.link');
    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      final titleEl = el.selectFirst('strong.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    return MPages(mangaList, false);
  }

  MPages _parseSearchResults(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('ul.card_lst li a');
    if (elements.isEmpty) elements = doc.select('div.card_item a');

    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      final titleEl = el.selectFirst('p.subj, strong.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    final nextPage = doc.selectFirst('a.pg_next');
    return MPages(mangaList, nextPage != null || mangaList.length >= 20);
  }
}

Webtoons main(MSource source) {
  return Webtoons(source: source);
}
