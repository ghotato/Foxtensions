// Madara WordPress Theme - Multisrc Framework
// This file is executed by the d4rt interpreter at runtime.
// It receives an MSource object as the first positional argument.

import 'package:foxlations/bridge_lib.dart';

MSource source;
String get baseUrl => source.baseUrl;
String get lang => source.lang;
String get dateFormat => source.dateFormat ?? 'MMMM dd, yyyy';
String get dateFormatLocale => source.dateFormatLocale ?? 'en_us';

// Some Madara sites use a different path for manga
String get mangaPath => 'manga';

bool supportsLatest() => true;

Map<String, String> getHeader(String url) {
  return {
    'Referer': baseUrl,
  };
}

Map<String, String> headers() {
  return {
    'Referer': baseUrl,
  };
}

Future<MPages> getPopular(int page) async {
  final client = Client();
  final url = '$baseUrl/$mangaPath/page/$page/?m_orderby=views';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseMangaList(doc);
}

Future<MPages> getLatestUpdates(int page) async {
  final client = Client();
  final url = '$baseUrl/$mangaPath/page/$page/?m_orderby=latest';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseMangaList(doc);
}

Future<MPages> search(String query, int page, FilterList filterList) async {
  final client = Client();
  final encodedQuery = Uri.encodeComponent(query);
  final url = '$baseUrl/page/$page/?s=$encodedQuery&post_type=wp-manga';
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  return _parseSearchResults(doc);
}

Future<MManga> getDetail(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);
  final manga = MManga();

  // Title
  final titleEl = doc.selectFirst('div.post-title h1, div.post-title h3');
  if (titleEl != null) {
    manga.name = titleEl.text;
  }

  // Cover image
  final imgEl = doc.selectFirst('div.summary_image img');
  if (imgEl != null) {
    manga.imageUrl = imgEl.getSrc();
  }

  // Author
  final authorEl = doc.selectFirst('div.author-content > a');
  if (authorEl != null) {
    manga.author = authorEl.text;
  }

  // Artist
  final artistEl = doc.selectFirst('div.artist-content > a');
  if (artistEl != null) {
    manga.artist = artistEl.text;
  }

  // Description
  final descEl = doc.selectFirst('div.description-summary div.summary__content');
  if (descEl == null) {
    final descAlt = doc.selectFirst('div.summary__content');
    if (descAlt != null) {
      manga.description = descAlt.text;
    }
  } else {
    manga.description = descEl.text;
  }

  // Status
  final statusElements = doc.select('div.post-status div.summary-content');
  if (statusElements.length >= 2) {
    final statusText = statusElements[1].text.toLowerCase();
    if (statusText.contains('ongoing')) {
      manga.status = 0;
    } else if (statusText.contains('completed')) {
      manga.status = 1;
    } else if (statusText.contains('hiatus')) {
      manga.status = 2;
    } else if (statusText.contains('canceled') || statusText.contains('cancelled')) {
      manga.status = 3;
    }
  }

  // Genres
  final genreElements = doc.select('div.genres-content a');
  final genres = <String>[];
  for (final el in genreElements) {
    genres.add(el.text);
  }
  manga.genre = genres;

  // Chapters — fetch via AJAX
  manga.chapters = await _getChapterList(url, res.body);

  return manga;
}

Future<List<dynamic>> getPageList(String url) async {
  final client = Client();
  final res = await client.get(url, headers: {'Referer': baseUrl});
  final doc = Document(res.body);

  final pages = <String>[];

  // Primary: div.page-break img
  final imgElements = doc.select('div.page-break img');
  if (imgElements.isNotEmpty) {
    for (final img in imgElements) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) {
        pages.add(src.trim());
      }
    }
  }

  // Fallback: li.blocks-gallery-item img
  if (pages.isEmpty) {
    final galleryImgs = doc.select('li.blocks-gallery-item img');
    for (final img in galleryImgs) {
      final src = img.getSrc();
      if (src != null && src.isNotEmpty) {
        pages.add(src.trim());
      }
    }
  }

  return pages;
}

List<dynamic> getFilterList() {
  return [];
}

List<dynamic> getSourcePreferences() {
  return [];
}

// --- Private helpers ---

MPages _parseMangaList(Document doc) {
  final mangaList = <MManga>[];

  final elements = doc.select('div.page-item-detail');
  for (final el in elements) {
    final manga = MManga();

    final titleEl = el.selectFirst('div.post-title a, h3.h5 a');
    if (titleEl != null) {
      manga.name = titleEl.text;
      manga.link = titleEl.attr('href');
    }

    final imgEl = el.selectFirst('img');
    if (imgEl != null) {
      manga.imageUrl = imgEl.getSrc();
    }

    if (manga.name != null && manga.link != null) {
      mangaList.add(manga);
    }
  }

  // Check for next page
  final nextPage = doc.selectFirst('div.nav-previous a, a.nextpostslink');
  final hasNextPage = nextPage != null;

  return MPages(list: mangaList, hasNextPage: hasNextPage);
}

MPages _parseSearchResults(Document doc) {
  final mangaList = <MManga>[];

  final elements = doc.select('div.c-tabs-item__content');
  for (final el in elements) {
    final manga = MManga();

    final titleEl = el.selectFirst('div.post-title a, h3 a');
    if (titleEl != null) {
      manga.name = titleEl.text;
      manga.link = titleEl.attr('href');
    }

    final imgEl = el.selectFirst('img');
    if (imgEl != null) {
      manga.imageUrl = imgEl.getSrc();
    }

    if (manga.name != null && manga.link != null) {
      mangaList.add(manga);
    }
  }

  final nextPage = doc.selectFirst('div.nav-previous a, a.nextpostslink');
  return MPages(list: mangaList, hasNextPage: nextPage != null);
}

Future<List<MChapter>> _getChapterList(String mangaUrl, String pageHtml) async {
  final client = Client();
  final chapters = <MChapter>[];

  // Extract manga ID from the page
  String? mangaId;
  final doc = Document(pageHtml);
  final holderEl = doc.selectFirst('[id^=manga-chapters-holder]');
  if (holderEl != null) {
    mangaId = holderEl.attr('data-id');
  }

  String chapterHtml = '';

  // Method 1: AJAX endpoint
  if (mangaId != null) {
    try {
      final ajaxRes = await client.post(
        '$baseUrl/wp-admin/admin-ajax.php',
        headers: {
          'Referer': baseUrl,
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        'action=manga_get_chapters&manga=$mangaId',
      );
      if (ajaxRes.statusCode == 200) {
        chapterHtml = ajaxRes.body;
      }
    } catch (_) {}
  }

  // Method 2: Fallback AJAX endpoint
  if (chapterHtml.isEmpty) {
    try {
      final fallbackRes = await client.post(
        '${mangaUrl}ajax/chapters/',
        headers: {
          'Referer': baseUrl,
          'X-Requested-With': 'XMLHttpRequest',
        },
        '',
      );
      if (fallbackRes.statusCode == 200) {
        chapterHtml = fallbackRes.body;
      }
    } catch (_) {}
  }

  if (chapterHtml.isNotEmpty) {
    final chapterDoc = Document(chapterHtml);
    final chapterElements = chapterDoc.select('li.wp-manga-chapter');

    for (final el in chapterElements) {
      final chapter = MChapter();
      final linkEl = el.selectFirst('a');
      if (linkEl != null) {
        chapter.name = linkEl.text.trim();
        chapter.url = linkEl.attr('href');
      }

      final dateEl = el.selectFirst('span.chapter-release-date, span.c-new-tag a');
      if (dateEl != null) {
        chapter.dateUpload = dateEl.text.trim();
      }

      if (chapter.url != null) {
        chapters.add(chapter);
      }
    }
  }

  return chapters;
}
