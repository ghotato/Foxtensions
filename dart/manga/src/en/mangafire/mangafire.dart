// MangaFire - Custom source with AJAX JSON API
// Uses mangafire.to with internal /ajax/ endpoints

import 'package:mangayomi/bridge_lib.dart';

class MangaFire extends MProvider {
  MangaFire({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=most_viewed&page=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=recently_updated&page=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/filter?keyword=$q&page=$page';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    final titleEl = doc.selectFirst('h1, div.manga-name h1');
    if (titleEl != null) manga.name = titleEl.text.trim();

    final imgEl = doc.selectFirst('div.poster img, img.poster');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    final authorEl = doc.selectFirst('div.meta a[href*=author], span.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    final descEl = doc.selectFirst('div.description, div.modal-body div.content, p.description');
    if (descEl != null) manga.description = descEl.text.trim();

    final genreEls = doc.select('div.genres a, a.genre');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    final statusEl = doc.selectFirst('span.status, div.status');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('releasing') || s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
      else if (s.contains('hiatus')) { manga.status = 2; }
    }

    // Chapters - try AJAX endpoint
    final chapters = <MChapter>[];
    // Extract manga ID from URL slug
    final slug = url.split('/').where((s) => s.isNotEmpty).last;

    try {
      final ajaxUrl = '$baseUrl/ajax/manga/$slug/chapter/en';
      final ajaxRes = await client.get(ajaxUrl, headers: {
        'Referer': url,
        'X-Requested-With': 'XMLHttpRequest',
      });
      final chDoc = Document(ajaxRes.body);
      final chEls = chDoc.select('a, li a');
      for (final el in chEls) {
        final ch = MChapter();
        ch.url = el.attr('href');
        ch.name = el.text.trim();
        if (ch.url != null && ch.name != null && ch.name!.isNotEmpty) chapters.add(ch);
      }
    } catch (_) {}

    // Fallback: chapters from page HTML
    if (chapters.isEmpty) {
      final chEls = doc.select('ul.chapter-list li a, div.chapter-list a');
      for (final el in chEls) {
        final ch = MChapter();
        ch.url = el.attr('href');
        final nameEl = el.selectFirst('span.name, span.chapter-name');
        ch.name = nameEl != null ? nameEl.text.trim() : el.text.trim();
        if (ch.url != null) chapters.add(ch);
      }
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final pages = <String>[];

    final imgEls = doc.select('div.read-content img, div.container-reader-chapter img, img.reader-img');
    for (final img in imgEls) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty && !src.contains('logo')) pages.add(src.trim());
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseList(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('div.unit a, div.item a.poster, div.manga-item a');
    if (elements.isEmpty) elements = doc.select('div.original a.unit');

    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      if (manga.link != null && !manga.link!.startsWith('http')) {
        manga.link = '$baseUrl${manga.link}';
      }
      final titleEl = el.selectFirst('div.info span.name, span.manga-name, div.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      // Fallback title from attr
      if (manga.name == null || manga.name!.isEmpty) {
        manga.name = el.attr('title') ?? '';
      }
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) mangaList.add(manga);
    }

    final nextPage = doc.selectFirst('a.page-link[rel=next], li.page-item.active + li a');
    return MPages(mangaList, nextPage != null || mangaList.length >= 20);
  }
}

MangaFire main(MSource source) {
  return MangaFire(source: source);
}
