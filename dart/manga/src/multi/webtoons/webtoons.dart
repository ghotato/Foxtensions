// Webtoons.com - Official webtoon platform
// Uses embedded JSON state + internal API

import 'package:mangayomi/bridge_lib.dart';

class Webtoons extends MProvider {
  Webtoons({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get lang => source.lang ?? 'en';

  String get _langPath {
    switch (lang) {
      case 'ko': return 'ko';
      case 'zh': return 'zh-hant';
      case 'th': return 'th';
      case 'id': return 'id';
      case 'es': return 'es';
      case 'fr': return 'fr';
      case 'de': return 'de';
      default: return 'en';
    }
  }

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/$_langPath/ranking/trending';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/$_langPath/dailySchedule';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/$_langPath/search?keyword=$q&page=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseSearchResults(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    final titleEl = doc.selectFirst('h1.subj, h3.subj');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Cover
    final imgEl = doc.selectFirst('span.thmb img, div.detail_header img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Author
    final authorEl = doc.selectFirst('a.author_area, span.author_area');
    if (authorEl != null) manga.author = authorEl.text.trim();

    // Description
    final descEl = doc.selectFirst('p.summary, div.detail_body p');
    if (descEl != null) manga.description = descEl.text.trim();

    // Genre
    final genreEls = doc.select('div.genre span, span.genre');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Status
    final statusEl = doc.selectFirst('p.day_info, span.txt_status');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('completed') || s.contains('end')) { manga.status = 1; }
      else { manga.status = 0; }
    }

    // Chapters - episodes list
    final chapters = <MChapter>[];
    final episodeEls = doc.select('#_listUl li a, ul.episode_lst li a');
    for (final el in episodeEls) {
      final ch = MChapter();
      ch.url = el.attr('href');
      final nameEl = el.selectFirst('span.subj span, span.ellipsis');
      ch.name = nameEl != null ? nameEl.text.trim() : el.text.trim();
      final dateEl = el.selectFirst('span.date, span.s_date');
      if (dateEl != null) ch.dateUpload = dateEl.text.trim();
      if (ch.url != null && ch.name != null) chapters.add(ch);
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final pages = <String>[];

    // Images in the viewer
    final imgEls = doc.select('div#_imageList img, div.viewer_img img, img._images');
    for (final img in imgEls) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) pages.add(src.trim());
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseList(String body) {
    final doc = Document(body);
    final mangaList = <MManga>[];

    // Webtoons ranking/top page
    var elements = doc.select('ul.webtoon_list li a.link');
    // Fallback: card list, daily schedule
    if (elements.isEmpty) elements = doc.select('ul.card_lst li a');
    if (elements.isEmpty) elements = doc.select('div.daily_card a, ul.daily_section li a');

    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      final titleEl = el.selectFirst('strong.title, p.subj, span.subj');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    return MPages(mangaList, false);
  }

  MPages _parseSearchResults(String body) {
    final doc = Document(body);
    final mangaList = <MManga>[];

    final elements = doc.select('ul.card_lst li a, div.card_item a, a.card_item');
    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      final titleEl = el.selectFirst('p.subj, span.subj, p.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    final nextPage = doc.selectFirst('a.pg_next, div.paginate a.on + a');
    return MPages(mangaList, nextPage != null || mangaList.length >= 20);
  }
}

Webtoons main(MSource source) {
  return Webtoons(source: source);
}
