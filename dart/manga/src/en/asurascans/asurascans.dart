// Asura Scans - Custom Next.js source (no longer MangaThemesia)
// Uses asurascans.com with Next.js hydration data

import 'package:mangayomi/bridge_lib.dart';

class AsuraScans extends MProvider {
  AsuraScans({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/manga?page=$page&order=rating';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/manga?page=$page&order=update';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/manga?page=$page&name=$q';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: {'Referer': '$baseUrl/'});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    final titleEl = doc.selectFirst('span.text-xl, h1');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Cover
    final imgEl = doc.selectFirst('img[alt=poster], div.relative img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Description
    final descEl = doc.selectFirst('span.font-medium.text-sm, div.desc p');
    if (descEl != null) manga.description = descEl.text.trim();

    // Genres
    final genreEls = doc.select('button.text-white, div.genres a, span.genre');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Status - look for status in info section
    final statusEl = doc.selectFirst('h3:contains(Status) + h3, span.status');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('ongoing')) { manga.status = 0; }
      else if (s.contains('completed')) { manga.status = 1; }
      else if (s.contains('hiatus')) { manga.status = 2; }
    }

    // Author
    final authorEl = doc.selectFirst('h3:contains(Author) + h3, span.author');
    if (authorEl != null) manga.author = authorEl.text.trim();

    // Chapters
    final chapters = <MChapter>[];
    final chEls = doc.select('div.scrollbar-thumb-themecolor div.group, div.chapter-list a, div.pl-4 a');
    for (final el in chEls) {
      final ch = MChapter();
      final linkEl = el.selectFirst('a');
      if (linkEl != null) {
        ch.url = linkEl.attr('href');
        final nameEl = linkEl.selectFirst('h3');
        ch.name = nameEl != null ? nameEl.text.trim() : linkEl.text.trim();
      } else {
        ch.url = el.attr('href');
        ch.name = el.text.trim();
      }
      // Date: second h3 sibling
      final dateEls = el.select('h3');
      if (dateEls.length >= 2) {
        ch.dateUpload = dateEls[1].text.trim();
      }
      if (ch.url != null && ch.name != null && ch.name!.isNotEmpty) chapters.add(ch);
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

    // Reader images
    final imgEls = doc.select('div.w-full img, div.container img, img.reader-img');
    for (final img in imgEls) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty &&
          !src.contains('logo') && !src.contains('icon') &&
          !src.contains('avatar') && !src.contains('loading') &&
          (src.contains('.jpg') || src.contains('.png') || src.contains('.webp') || src.contains('.jpeg'))) {
        pages.add(src.trim());
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseList(Document doc) {
    final mangaList = <MManga>[];

    // Next.js grid layout
    var elements = doc.select('div.grid a[href*=series], div.grid > a');
    // Fallback
    if (elements.isEmpty) elements = doc.select('div.bsx a, div.bs a');

    for (final el in elements) {
      final manga = MManga();
      manga.link = el.attr('href');
      if (manga.link != null && !manga.link!.startsWith('http')) {
        manga.link = '$baseUrl${manga.link}';
      }
      final titleEl = el.selectFirst('span.block, span.text-sm, div.title');
      if (titleEl != null) manga.name = titleEl.text.trim();
      if (manga.name == null || manga.name!.isEmpty) {
        manga.name = el.attr('title') ?? '';
      }
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();
      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) mangaList.add(manga);
    }

    final nextPage = doc.selectFirst('a:contains(Next), a.flex.bg-themecolor');
    return MPages(mangaList, nextPage != null || mangaList.length >= 20);
  }
}

AsuraScans main(MSource source) {
  return AsuraScans(source: source);
}
