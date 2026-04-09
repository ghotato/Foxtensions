// MangaThemesia - Multisrc Framework
// Class-based multisrc framework.

import 'package:foxlations/bridge_lib.dart';

class MangaThemesia extends MProvider {
  MangaThemesia({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get mangaDir => source.additionalParams ?? 'manga';

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/$mangaDir/?page=$page&order=popular';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/$mangaDir/?page=$page&order=update';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final encodedQuery = Uri.encodeComponent(query);
    final url = '$baseUrl/page/$page/?s=$encodedQuery';
    final res = await client.get(url, headers: {'Referer': baseUrl});
    return _parseMangaList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: {'Referer': baseUrl});
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    var titleEl = doc.selectFirst('h1.entry-title');
    if (titleEl == null) titleEl = doc.selectFirst('.ts-breadcrumb li:last-child span');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Cover
    var imgEl = doc.selectFirst('div.thumb img');
    if (imgEl == null) imgEl = doc.selectFirst('div[itemprop=image] img');
    if (imgEl == null) imgEl = doc.selectFirst('div.summary_image img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();

    // Description
    var descEl = doc.selectFirst('div.entry-content[itemprop=description]');
    if (descEl == null) descEl = doc.selectFirst('div[itemprop=description]');
    if (descEl == null) descEl = doc.selectFirst('div.desc');
    if (descEl != null) manga.description = descEl.text.trim();

    // Author & Artist & Status
    final infoItems = doc.select('div.tsinfo div.imptdt, span.imptdt');
    for (final item in infoItems) {
      final text = item.text.toLowerCase();
      final value = item.selectFirst('i, a');
      if (value != null) {
        if (text.contains('author')) manga.author = value.text.trim();
        if (text.contains('artist')) manga.artist = value.text.trim();
        if (text.contains('status')) {
          final s = value.text.toLowerCase();
          if (s.contains('ongoing')) { manga.status = 0; }
          else if (s.contains('completed')) { manga.status = 1; }
          else if (s.contains('hiatus')) { manga.status = 2; }
          else if (s.contains('dropped') || s.contains('cancel')) { manga.status = 3; }
        }
      }
    }

    // Status fallback
    if (manga.status == null) {
      final statusEl = doc.selectFirst('div.post-status div.summary-content');
      if (statusEl != null) {
        final s = statusEl.text.toLowerCase();
        if (s.contains('ongoing')) { manga.status = 0; }
        else if (s.contains('completed')) { manga.status = 1; }
      }
    }

    // Genres
    var genreEls = doc.select('span.mgen a');
    if (genreEls.isEmpty) genreEls = doc.select('div.gnr a');
    if (genreEls.isEmpty) genreEls = doc.select('div.seriestugenre a');
    if (genreEls.isNotEmpty) {
      manga.genre = genreEls.map((e) => e.text.trim()).where((e) => e.isNotEmpty).toList();
    }

    // Chapters
    final chapterElements = doc.select('#chapterlist li');
    if (chapterElements.isEmpty) {
      final altChapters = doc.select('ul.clstyle li');
      _parseChapters(altChapters, manga);
    } else {
      _parseChapters(chapterElements, manga);
    }

    return manga;
  }

  void _parseChapters(List<dynamic> elements, MManga manga) {
    final chapters = <MChapter>[];
    for (final el in elements) {
      final chapter = MChapter();
      final linkEl = el.selectFirst('a');
      if (linkEl != null) {
        chapter.url = linkEl.attr('href');
        final nameEl = el.selectFirst('span.chapternum');
        if (nameEl == null) {
          final altName = el.selectFirst('span.chapter-num');
          chapter.name = altName != null ? altName.text.trim() : linkEl.text.trim();
        } else {
          chapter.name = nameEl.text.trim();
        }
      }
      final dateEl = el.selectFirst('span.chapterdate');
      if (dateEl == null) {
        final altDate = el.selectFirst('span.chapter-date');
        if (altDate != null) chapter.dateUpload = altDate.text.trim();
      } else {
        chapter.dateUpload = dateEl.text.trim();
      }
      if (chapter.url != null) chapters.add(chapter);
    }
    manga.chapters = chapters;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final res = await client.get(url, headers: {'Referer': url});
    final body = res.body;
    final pages = <String>[];
    // Diagnostic trail. Returned as fake page URLs on failure so we can see
    // them in the [Service] log without relying on d4rt's print().
    final diag = <String>[];
    diag.add('DEBUG bodyLen=${body.length}');
    diag.add('DEBUG containsImages=${body.contains('"images"')}');

    // Method 1: Look for the `"images":[...]` array directly. Uses the same
    // proven pattern as mangayomi-extensions/multisrc/mangareader: non-greedy
    // `.*?` with the closing `]` as the terminator. Works for ts_reader.run,
    // tcl_reader, and any other variant since they all use the same key.
    final imagesMatch =
        RegExp(r'"images"\s*:\s*(\[.*?\])', dotAll: true).firstMatch(body);
    if (imagesMatch != null) {
      final raw = imagesMatch.group(1)!;
      diag.add('DEBUG regexMatched rawLen=${raw.length}');
      diag.add('DEBUG rawHead=${raw.substring(0, raw.length > 120 ? 120 : raw.length)}');
      try {
        final list = jsonDecode(raw) as List;
        for (final p in list) {
          if (p is String && p.isNotEmpty) pages.add(p);
        }
        diag.add('DEBUG jsonDecodeParsed=${pages.length}');
      } catch (e) {
        diag.add('DEBUG jsonDecodeFailed=$e');
        // Fallback: extract URLs by regex.
        final urlPattern = RegExp(r'"(https?:[^"]+)"');
        for (final m in urlPattern.allMatches(raw)) {
          final u = m.group(1)!.replaceAll(r'\/', '/');
          if (u.isNotEmpty) pages.add(u);
        }
        diag.add('DEBUG regexExtractGot=${pages.length}');
      }
    } else {
      diag.add('DEBUG regexNotMatched');
    }

    // Method 2: HTML img tags in the reader area.
    if (pages.isEmpty) {
      final doc = Document(body);
      var imgElements = doc.select(
          '#readerarea p img, #readerarea img, div.rdminimal img, div.read-content img, div.entry-content img');
      diag.add('DEBUG selectorFound=${imgElements.length}');
      for (final img in imgElements) {
        final src = img.getSrc();
        if (src != null &&
            src.isNotEmpty &&
            !src.startsWith('data:') &&
            !src.contains('logo') &&
            !src.contains('icon') &&
            !src.contains('avatar') &&
            !src.contains('loading')) {
          pages.add(src.trim());
        }
      }
      diag.add('DEBUG selectorPages=${pages.length}');
    }

    // If everything failed, return the diagnostic strings instead of an
    // empty list so the [Service] log surfaces what happened. The reader
    // will show garbage URLs for one frame but at least we get visibility.
    if (pages.isEmpty) return diag;

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseMangaList(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('div.bsx');
    if (elements.isEmpty) elements = doc.select('div.bs');
    if (elements.isEmpty) elements = doc.select('div.listupd .bs');
    if (elements.isEmpty) elements = doc.select('.utao .uta .imgu');

    for (final el in elements) {
      final manga = MManga();
      final linkEl = el.selectFirst('a');
      if (linkEl != null) {
        manga.link = linkEl.attr('href');
        manga.name = linkEl.attr('title') ?? '';
      }
      if (manga.name == null || manga.name!.isEmpty) {
        final titleEl = el.selectFirst('div.tt, span.ntitle');
        if (titleEl != null) manga.name = titleEl.text.trim();
      }
      if (manga.name == null || manga.name!.isEmpty) {
        final altTitle = el.selectFirst('a');
        if (altTitle != null) manga.name = altTitle.text.trim();
      }
      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();

      if (manga.name != null && manga.link != null) mangaList.add(manga);
    }

    var nextPage = doc.selectFirst('a.next.page-numbers, div.hpage a.r, div.pagination .next');
    final hasNext = nextPage != null || mangaList.length >= 20;
    return MPages(mangaList, hasNext);
  }
}

MangaThemesia main(MSource source) {
  return MangaThemesia(source: source);
}
