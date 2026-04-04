// Naver Webtoon (comic.naver.com) - Korean webtoons

import 'package:mangayomi/bridge_lib.dart';

class NaverWebtoon extends MProvider {
  NaverWebtoon({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get mobileUrl => 'https://m.comic.naver.com';

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$mobileUrl/webtoon/weekday';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$mobileUrl/webtoon/weekday';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$mobileUrl/search?keyword=$q';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$mobileUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    final titleEl = doc.selectFirst('h2.EpisodeListInfo__title, span.title');
    if (titleEl != null) manga.name = titleEl.text.trim();

    final imgEl = doc.selectFirst('div.EpisodeListInfo__thumbnail img, span.thmb img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    final authorEl = doc.selectFirst('span.author, a.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    final descEl = doc.selectFirst('p.EpisodeListInfo__summary, div.detail p');
    if (descEl != null) manga.description = descEl.text.trim();

    final genreEls = doc.select('span.genre, div.tag_area a');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Episodes
    final chapters = <MChapter>[];
    final epEls = doc.select('ul.EpisodeListList__list li a, ul.section_episode_list li a');
    for (final el in epEls) {
      final ch = MChapter();
      ch.url = el.attr('href');
      final nameEl = el.selectFirst('span.EpisodeListList__title, span.title');
      ch.name = nameEl != null ? nameEl.text.trim() : el.text.trim();
      final dateEl = el.selectFirst('span.date, span.EpisodeListList__meta--date');
      if (dateEl != null) ch.dateUpload = dateEl.text.trim();
      if (ch.url != null) chapters.add(ch);
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$mobileUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final pages = <String>[];

    final imgEls = doc.select('div.wt_viewer img, div#comic_view_area img');
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

  MPages _parseList(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('a.DailyListItem, ul.list_toon li a, div.item a');
    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      final titleEl = el.selectFirst('span.text, span.title, p.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    return MPages(mangaList, false);
  }
}

NaverWebtoon main(MSource source) {
  return NaverWebtoon(source: source);
}
