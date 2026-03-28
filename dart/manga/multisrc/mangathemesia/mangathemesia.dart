// MangaThemesia - Multisrc Framework
// Executed by d4rt interpreter at runtime.
// Receives MSource as first positional argument.

import 'package:foxlations/bridge_lib.dart';

MSource source;
String get baseUrl => source.baseUrl;
String get lang => source.lang;

bool supportsLatest() => true;

Map<String, String> headers() {
  return {'Referer': baseUrl};
}

Map<String, String> getHeader(String url) {
  return {'Referer': baseUrl};
}

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = '$baseUrl/manga/?page=$page&order=popular';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseMangaList(doc);
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = '$baseUrl/manga/?page=$page&order=update';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseMangaList(doc);
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final encodedQuery = Uri.encodeComponent(query);
  final url = '$baseUrl/page/$page/?s=$encodedQuery';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseMangaList(doc);
}

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  // Title
  final titleEl = doc.selectFirst('h1.entry-title');
  if (titleEl != null) {
    manga.name = titleEl.text;
  }

  // Cover
  final imgEl = doc.selectFirst('div.thumb img, div.summary_image img');
  if (imgEl != null) {
    manga.imageUrl = imgEl.getSrc();
  }

  // Author
  final authorEl = doc.selectFirst('span.imptdt:contains(Author) i, div.author-content a');
  if (authorEl != null) {
    manga.author = authorEl.text;
  }

  // Description
  final descEl = doc.selectFirst('div.entry-content[itemprop=description], div[itemprop=description]');
  if (descEl != null) {
    manga.description = descEl.text;
  }

  // Status
  final statusEl = doc.selectFirst('span.imptdt:contains(Status) i, div.tsinfo div.imptdt:nth-child(1) i');
  if (statusEl != null) {
    final statusText = statusEl.text.toLowerCase();
    if (statusText.contains('ongoing')) {
      manga.status = 0;
    } else if (statusText.contains('completed')) {
      manga.status = 1;
    } else if (statusText.contains('hiatus')) {
      manga.status = 2;
    }
  }

  // Genres
  final genreElements = doc.select('span.mgen a, div.wd-full span.mgen a');
  final genres = <String>[];
  for (final el in genreElements) {
    genres.add(el.text);
  }
  manga.genre = genres;

  // Chapters
  final chapterElements = doc.select('#chapterlist li, ul.clstyle li');
  final chapters = <MChapter>[];
  for (final el in chapterElements) {
    final chapter = MChapter();
    final linkEl = el.selectFirst('a');
    if (linkEl != null) {
      chapter.url = linkEl.attr('href');
      final nameEl = el.selectFirst('span.chapternum, span.chapter-num');
      chapter.name = nameEl != null ? nameEl.text : linkEl.text.trim();
    }

    final dateEl = el.selectFirst('span.chapterdate, span.chapter-date');
    if (dateEl != null) {
      chapter.dateUpload = dateEl.text.trim();
    }

    if (chapter.url != null) {
      chapters.add(chapter);
    }
  }
  manga.chapters = chapters;

  return manga;
}

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);

  final pages = <String>[];

  // Primary: #readerarea img
  final imgElements = doc.select('#readerarea img');
  for (final img in imgElements) {
    final src = img.getSrc();
    if (src != null && src.isNotEmpty && !src.contains('logo') && !src.contains('icon')) {
      pages.add(src.trim());
    }
  }

  // Fallback: try to find JSON images in script tags
  if (pages.isEmpty) {
    final body = res.body;
    final tsReaderMatch = RegExp(r'ts_reader\.run\((\{.*?\})\)', dotAll: true);
    final match = tsReaderMatch.firstMatch(body);
    if (match != null) {
      // Parse the JSON for image sources
      final jsonStr = match.group(1);
      if (jsonStr != null && jsonStr.contains('"images"')) {
        final imagesMatch = RegExp(r'"images"\s*:\s*\[(.*?)\]', dotAll: true);
        final imgMatch = imagesMatch.firstMatch(jsonStr);
        if (imgMatch != null) {
          final urlPattern = RegExp(r'"(https?://[^"]+)"');
          final urls = urlPattern.allMatches(imgMatch.group(1) ?? '');
          for (final u in urls) {
            pages.add(u.group(1)!);
          }
        }
      }
    }
  }

  return pages;
}

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  // Try multiple selector patterns
  var elements = doc.select('div.bsx');
  if (elements.isEmpty) {
    elements = doc.select('div.bs');
  }
  if (elements.isEmpty) {
    elements = doc.select('div.listupd .bs');
  }

  for (final el in elements) {
    final manga = MManga();

    final linkEl = el.selectFirst('a');
    if (linkEl != null) {
      manga.link = linkEl.attr('href');
    }

    final titleEl = el.selectFirst('div.tt, a[title]');
    if (titleEl != null) {
      manga.name = titleEl.text.trim();
    }
    if (manga.name == null || manga.name!.isEmpty) {
      final altTitle = el.selectFirst('a');
      if (altTitle != null) {
        manga.name = altTitle.attr('title') ?? altTitle.text.trim();
      }
    }

    final imgEl = el.selectFirst('img');
    if (imgEl != null) {
      manga.imageUrl = imgEl.getSrc();
    }

    if (manga.name != null && manga.link != null) {
      mangaList.add(manga);
    }
  }

  final nextPage = doc.selectFirst('a.next.page-numbers, div.hpage a.r');
  return MPages(list: mangaList, hasNextPage: nextPage != null);
}
