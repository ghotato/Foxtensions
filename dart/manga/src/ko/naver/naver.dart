// Naver Webtoon - Uses comic.naver.com API

import 'package:foxlations/bridge_lib.dart';

class NaverWebtoon extends MProvider {
  NaverWebtoon({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://comic.naver.com';
  String get mobileUrl => 'https://m.comic.naver.com';

  Map<String, String> _getHeaders() {
    return {
      'Referer': '$baseUrl/',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
    };
  }

  @override
  Future<MPages> getPopular(int page) async {
    // Use weekday list sorted by view count
    final url = '$mobileUrl/webtoon/weekday';
    final res = await client.get(url, headers: _getHeaders());
    return _parseHtmlList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$mobileUrl/webtoon/weekday?order=update';
    final res = await client.get(url, headers: _getHeaders());
    return _parseHtmlList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/api/search/webtoon?keyword=$q&page=$page';
    final res = await client.get(url, headers: _getHeaders());
    return _parseSearchApi(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final manga = MManga();

    // Extract titleId from URL
    final titleIdMatch = RegExp(r'titleId=(\d+)').firstMatch(url);
    if (titleIdMatch == null) return manga;
    final titleId = titleIdMatch.group(1)!;

    // Get manga info from HTML page (og tags)
    final pageUrl = '$mobileUrl/webtoon/list?titleId=$titleId';
    final pageRes = await client.get(pageUrl, headers: _getHeaders());
    final doc = Document(pageRes.body);

    final ogTitle = doc.selectFirst('meta[property=og:title]');
    if (ogTitle != null) manga.name = ogTitle.attr('content');

    final ogImage = doc.selectFirst('meta[property=og:image]');
    if (ogImage != null) manga.imageUrl = ogImage.attr('content');

    final ogDesc = doc.selectFirst('meta[property=og:description]');
    if (ogDesc != null) manga.description = ogDesc.attr('content');

    final authorEl = doc.selectFirst('span.author, a.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    // Fetch chapters via API (paginated)
    final chapters = <MChapter>[];
    var page = 1;
    var hasMore = true;

    while (hasMore && page <= 100) {
      final apiUrl = '$baseUrl/api/article/list?titleId=$titleId&page=$page';
      final apiRes = await client.get(apiUrl, headers: _getHeaders());
      final body = apiRes.body;

      // Parse articleList from JSON
      final articles = RegExp(
        r'"no"\s*:\s*(\d+).*?"subtitle"\s*:\s*"([^"]*)".*?"serviceDateDescription"\s*:\s*"([^"]*)"',
        dotAll: true,
      );

      // Split by individual article objects
      final objPattern = RegExp(r'\{[^{}]*"no"\s*:\s*\d+[^{}]*"subtitle"[^{}]*\}', dotAll: true);
      var found = 0;
      for (final obj in objPattern.allMatches(body)) {
        final str = obj.group(0)!;
        final noMatch = RegExp(r'"no"\s*:\s*(\d+)').firstMatch(str);
        final subMatch = RegExp(r'"subtitle"\s*:\s*"([^"]*)"').firstMatch(str);
        final dateMatch = RegExp(r'"serviceDateDescription"\s*:\s*"([^"]*)"').firstMatch(str);

        if (noMatch != null) {
          final ch = MChapter();
          final no = noMatch.group(1)!;
          ch.name = subMatch?.group(1) ?? 'Episode $no';
          ch.url = '$mobileUrl/webtoon/detail?titleId=$titleId&no=$no';
          if (dateMatch != null) ch.dateUpload = dateMatch.group(1);
          chapters.add(ch);
          found++;
        }
      }

      // Check if there are more pages
      hasMore = found >= 20;
      page++;
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(url, headers: _getHeaders());
    final doc = Document(res.body);
    final pages = <String>[];

    // Desktop viewer: .wt_viewer img
    var imgEls = doc.select('div.wt_viewer img');
    for (final img in imgEls) {
      final src = img.attr('src');
      if (src != null && src.isNotEmpty && src.startsWith('http')) {
        pages.add(src.trim());
      }
    }

    // Mobile fallback: .toon_view_lst img (uses data-src)
    if (pages.isEmpty) {
      imgEls = doc.select('div.toon_view_lst img');
      for (final img in imgEls) {
        final src = img.attr('data-src') ?? img.attr('src');
        if (src != null && src.isNotEmpty && src.startsWith('http')) {
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

  MPages _parseHtmlList(Document doc) {
    final mangaList = <MManga>[];

    // Collect adult titleIds from li items with badge.adult
    final adultIds = <String>{};
    final adultItems = doc.select('li.item span.badge.adult');
    for (final badge in adultItems) {
      // The badge text won't help, but we can find titleIds from nearby links
    }
    // Alternative: select li.item elements that contain badge.adult
    final allItems = doc.select('ul.list_toon li.item');
    for (final li in allItems) {
      final badge = li.selectFirst('span.badge.adult');
      if (badge != null) {
        final link = li.selectFirst('a.link');
        if (link != null) {
          final href = link.attr('href') ?? '';
          final idMatch = RegExp(r'titleId=(\d+)').firstMatch(href);
          if (idMatch != null) adultIds.add(idMatch.group(1)!);
        }
      }
    }

    var elements = doc.select('ul.list_toon li.item a.link');
    if (elements.isEmpty) elements = doc.select('div.area_toon a.link_thumbnail');

    for (final el in elements) {
      final manga = MManga();
      var link = el.attr('href');
      if (link != null && !link.startsWith('http')) {
        link = '$mobileUrl$link';
      }
      // Check if this title is age-restricted
      final idMatch = RegExp(r'titleId=(\d+)').firstMatch(link ?? '');
      final isAdult = idMatch != null && adultIds.contains(idMatch.group(1));
      manga.link = isAdult ? '$link#adult' : link;
      final titleEl = el.selectFirst('strong.title span.title_text, strong.title, span.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    return MPages(mangaList, false);
  }

  MPages _parseSearchApi(String body) {
    final mangaList = <MManga>[];

    // Each search result has "titleId" at its top level (not nested).
    // tagList/communityArtists use "id"/"artistId", not "titleId", so we won't
    // get false positives. For each "titleId" hit, scan forward for the fields.
    final titleIdRegex = RegExp(r'"titleId"\s*:\s*(\d+)');
    for (final idMatch in titleIdRegex.allMatches(body)) {
      final end = (idMatch.start + 2000).clamp(0, body.length);
      final window = body.substring(idMatch.start, end);

      final nameMatch = RegExp(r'"titleName"\s*:\s*"([^"]*)"').firstMatch(window);
      final imgMatch = RegExp(r'"thumbnailUrl"\s*:\s*"([^"]*)"').firstMatch(window);

      if (nameMatch != null) {
        final manga = MManga();
        manga.name = nameMatch.group(1);
        manga.link = '$mobileUrl/webtoon/list?titleId=${idMatch.group(1)}';
        if (imgMatch != null) manga.imageUrl = imgMatch.group(1);
        mangaList.add(manga);
      }
    }

    final hasNext = body.contains('"nextPage":') && !body.contains('"nextPage":0');
    return MPages(mangaList, hasNext);
  }
}

NaverWebtoon main(MSource source) {
  return NaverWebtoon(source: source);
}
