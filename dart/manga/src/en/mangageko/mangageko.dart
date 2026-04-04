// MangaGeko (mgeko.cc) - HTML scraping source

import 'package:mangayomi/bridge_lib.dart';

class MangaGeko extends MProvider {
  MangaGeko({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/browse-comics/?results=$page&filter=views';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/browse-comics/?results=$page&filter=Updated';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/?s=$q&post_type=wp-manga&paged=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    final titleEl = doc.selectFirst('h1, div.manga-title h1');
    if (titleEl != null) manga.name = titleEl.text.trim();

    final imgEl = doc.selectFirst('div.manga-poster img, div.thumb img, img.manga-cover');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    final authorEl = doc.selectFirst('div.author a, span.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    final descEl = doc.selectFirst('div.description p, div.manga-summary p, div.summary-content');
    if (descEl != null) manga.description = descEl.text.trim();

    final genreEls = doc.select('div.genres a, div.genre a, span.genre a');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    final statusEl = doc.selectFirst('div.status span, span.status');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
    }

    final chapters = <MChapter>[];
    final chEls = doc.select('div.chapter-list a, ul.chapter-list li a, div.chapters-list a');
    for (final el in chEls) {
      final ch = MChapter();
      ch.url = el.attr('href');
      ch.name = el.text.trim();
      final dateEl = el.selectFirst('span.date, span.chapter-date');
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

    final imgEls = doc.select('div.read-content img, div.chapter-content img, div.reader img');
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

    // Try comic-card based selectors (current mgeko layout)
    var elements = doc.select('div.comic-card a, div.comic-item a');
    // Fallback to older selectors
    if (elements.isEmpty) elements = doc.select('div.manga-item a, div.list-item a.item, div.page-item-detail a');
    if (elements.isEmpty) elements = doc.select('div.item a, div.col-item a');

    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      if (manga.link != null && !manga.link!.startsWith('http')) {
        manga.link = '$baseUrl${manga.link}';
      }
      final titleEl = el.selectFirst('div.comic-card__title, h3, span.title, div.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      if (manga.name == null || manga.name!.isEmpty) manga.name = el.attr('title') ?? '';
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) mangaList.add(manga);
    }

    final nextPage = doc.selectFirst('a.next, a.page-next, li.active + li a');
    return MPages(mangaList, nextPage != null || mangaList.length >= 20);
  }
}

MangaGeko main(MSource source) {
  return MangaGeko(source: source);
}
