// MangaThemesia - Multisrc Framework
// Based on Tachiyomi/Keiyoushi MangaThemesia implementation
// Executed by d4rt interpreter at runtime.

import 'package:foxlations/bridge_lib.dart';

MSource source;

void main(MSource s) {
  source = s;
}

String get baseUrl => source.baseUrl;
String get lang => source.lang;

// Configurable manga directory (some sites use /comics/, /series/, etc)
String get mangaDir => source.additionalParams ?? 'manga';

bool supportsLatest() => true;

Map<String, String> headers() => {'Referer': baseUrl};
Map<String, String> getHeader(String url) => {'Referer': baseUrl};

// --- Popular / Latest / Search ---

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = '$baseUrl/$mangaDir/?page=$page&order=popular';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = '$baseUrl/$mangaDir/?page=$page&order=update';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final encodedQuery = Uri.encodeComponent(query);
  final url = '$baseUrl/page/$page/?s=$encodedQuery';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

// --- Manga Detail ---

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  // Title
  var titleEl = doc.selectFirst('h1.entry-title');
  if (titleEl == null) titleEl = doc.selectFirst('.ts-breadcrumb li:last-child span');
  if (titleEl != null) manga.name = titleEl.text.trim();

  // Cover image
  var imgEl = doc.selectFirst('div.thumb img');
  if (imgEl == null) imgEl = doc.selectFirst('div[itemprop=image] img');
  if (imgEl == null) imgEl = doc.selectFirst('div.summary_image img');
  if (imgEl != null) manga.imageUrl = imgEl.getSrc();

  // Description
  var descEl = doc.selectFirst('div.entry-content[itemprop=description]');
  if (descEl == null) descEl = doc.selectFirst('div[itemprop=description]');
  if (descEl == null) descEl = doc.selectFirst('div.desc');
  if (descEl != null) manga.description = descEl.text.trim();

  // Author & Artist — parse from info section
  final infoItems = doc.select('div.tsinfo div.imptdt, span.imptdt');
  for (final item in infoItems) {
    final text = item.text.toLowerCase();
    final value = item.selectFirst('i, a');
    if (value != null) {
      if (text.contains('author')) manga.author = value.text.trim();
      if (text.contains('artist')) manga.artist = value.text.trim();
      if (text.contains('status')) {
        final s = value.text.toLowerCase();
        if (s.contains('ongoing')) manga.status = 0;
        else if (s.contains('completed')) manga.status = 1;
        else if (s.contains('hiatus')) manga.status = 2;
        else if (s.contains('dropped') || s.contains('cancel')) manga.status = 3;
      }
    }
  }

  // Status fallback — from post-status section
  if (manga.status == null) {
    final statusEl = doc.selectFirst('div.post-status div.summary-content');
    if (statusEl != null) {
      final s = statusEl.text.toLowerCase();
      if (s.contains('ongoing')) manga.status = 0;
      else if (s.contains('completed')) manga.status = 1;
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
      // Chapter name from specific element or link text
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

// --- Page List ---

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': url});
  final body = res.body;
  final pages = <String>[];

  // Method 1 (preferred): Extract from ts_reader.run() JSON
  final tsMatch = RegExp(r'ts_reader\.run\((\{.*?\})\)', dotAll: true).firstMatch(body);
  if (tsMatch != null) {
    final jsonStr = tsMatch.group(1)!;
    final imagesMatch = RegExp(r'"images"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(jsonStr);
    if (imagesMatch != null) {
      final urlPattern = RegExp(r'"(https?://[^"]+)"');
      for (final m in urlPattern.allMatches(imagesMatch.group(1)!)) {
        pages.add(m.group(1)!);
      }
    }
  }

  // Method 2: HTML img tags in reader area
  if (pages.isEmpty) {
    final doc = Document(body);
    final imgElements = doc.select('#readerarea img');
    for (final img in imgElements) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty &&
          !src.contains('logo') && !src.contains('icon') &&
          !src.contains('avatar') && !src.contains('loading')) {
        pages.add(src.trim());
      }
    }
  }

  return pages;
}

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

// --- Helpers ---

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  // Try multiple selector patterns used by MangaThemesia sites
  var elements = doc.select('div.bsx');
  if (elements.isEmpty) elements = doc.select('div.bs');
  if (elements.isEmpty) elements = doc.select('div.listupd .bs');
  if (elements.isEmpty) elements = doc.select('.utao .uta .imgu');

  for (final el in elements) {
    final manga = MManga();

    final linkEl = el.selectFirst('a');
    if (linkEl != null) {
      manga.link = linkEl.attr('href');
      // Title from title attribute (most reliable)
      manga.name = linkEl.attr('title') ?? '';
    }

    // Fallback title from text
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

  final nextPage = doc.selectFirst('a.next.page-numbers, div.hpage a.r, div.pagination .next');
  return MPages(list: mangaList, hasNextPage: nextPage != null);
}
