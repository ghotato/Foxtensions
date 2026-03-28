// MangaBox (Manganato/Mangakakalot) - Multisrc Framework
// Executed by d4rt interpreter at runtime.

import 'package:foxlations/bridge_lib.dart';

MSource source;
String get baseUrl => source.baseUrl;
String get lang => source.lang;

bool supportsLatest() => true;

Map<String, String> headers() => {'Referer': baseUrl};
Map<String, String> getHeader(String url) => {'Referer': baseUrl};

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = '$baseUrl/manga-list/hot-manga?page=$page';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = '$baseUrl/manga-list/latest-manga?page=$page';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final normalized = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  final url = '$baseUrl/search/story/$normalized?page=$page';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  return _parseMangaList(Document(res.body));
}

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  final titleEl = doc.selectFirst('h1, div.story-info-right h1');
  if (titleEl != null) manga.name = titleEl.text;

  final imgEl = doc.selectFirst('span.info-image img, div.story-info-left img');
  if (imgEl != null) manga.imageUrl = imgEl.getSrc();

  final descEl = doc.selectFirst('div#panel-story-info-description, div.panel-story-info-description');
  if (descEl != null) manga.description = descEl.text;

  final tableRows = doc.select('table.variations-tableInfo tr, td.table-label');
  for (final row in tableRows) {
    final label = row.selectFirst('td.table-label, label.info-title');
    final value = row.selectFirst('td.table-value, td.table-value a');
    if (label != null && value != null) {
      final labelText = label.text.toLowerCase();
      if (labelText.contains('author')) manga.author = value.text;
      if (labelText.contains('status')) {
        final s = value.text.toLowerCase();
        if (s.contains('ongoing')) manga.status = 0;
        else if (s.contains('completed')) manga.status = 1;
      }
      if (labelText.contains('genre')) {
        manga.genre = value.text.split(RegExp(r'[-,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
  }

  // Chapters
  final chapterElements = doc.select('ul.row-content-chapter li, div.chapter-list div.row');
  final chapters = <MChapter>[];
  for (final el in chapterElements) {
    final chapter = MChapter();
    final linkEl = el.selectFirst('a');
    if (linkEl != null) {
      chapter.name = linkEl.text.trim();
      chapter.url = linkEl.attr('href');
    }
    final dateEl = el.selectFirst('span.chapter-time, span');
    if (dateEl != null) chapter.dateUpload = dateEl.text.trim();
    if (chapter.url != null) chapters.add(chapter);
  }
  manga.chapters = chapters;

  return manga;
}

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final pages = <String>[];

  final imgElements = doc.select('div.container-chapter-reader img, div.panel-read-story img');
  for (final img in imgElements) {
    final src = img.getSrc();
    if (src != null && src.isNotEmpty) pages.add(src.trim());
  }

  return pages;
}

List<dynamic> getFilterList() => [];
List<dynamic> getSourcePreferences() => [];

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  var elements = doc.select('div.content-genres-item');
  if (elements.isEmpty) elements = doc.select('div.search-story-item');
  if (elements.isEmpty) elements = doc.select('div.story_item');

  for (final el in elements) {
    final manga = MManga();
    final linkEl = el.selectFirst('a.genres-item-img, a.item-img, a');
    if (linkEl != null) {
      manga.link = linkEl.attr('href');
      manga.name = linkEl.attr('title') ?? '';
    }
    final imgEl = el.selectFirst('img');
    if (imgEl != null) manga.imageUrl = imgEl.getSrc();
    final titleEl = el.selectFirst('h3 a');
    if (titleEl != null && (manga.name == null || manga.name!.isEmpty)) {
      manga.name = titleEl.text.trim();
    }
    if (manga.name != null && manga.link != null) mangaList.add(manga);
  }

  final nextPage = doc.selectFirst('a.page-next, a.page-blue.page-last');
  return MPages(list: mangaList, hasNextPage: nextPage != null);
}
