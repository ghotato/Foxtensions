// MangaFire - Based on keiyoushi's implementation
// Uses mangafire.to with AJAX endpoints

import 'package:mangayomi/bridge_lib.dart';

class MangaFire extends MProvider {
  MangaFire({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  Map<String, String> get _headers => {
    'Referer': '$baseUrl/',
  };

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=most_viewed&language%5B%5D=en&page=$page';
    final res = await client.get(url, headers: _headers);
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=recently_updated&language%5B%5D=en&page=$page';
    final res = await client.get(url, headers: _headers);
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/filter?keyword=$q&language%5B%5D=en&page=$page';
    final res = await client.get(url, headers: _headers);
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: _headers);
    final doc = Document(res.body);
    final manga = MManga();

    // Title
    final titleEl = doc.selectFirst('h1');
    if (titleEl != null) {
      manga.name = titleEl.text.trim();
    }

    // Cover image
    final imgEl = doc.selectFirst('.poster img');
    if (imgEl != null) {
      manga.imageUrl = imgEl.getSrc();
    }

    // Description
    final descEl = doc.selectFirst('#synopsis .modal-content');
    if (descEl != null) {
      manga.description = descEl.text.trim();
    }

    // Status from .info > p
    final statusEl = doc.selectFirst('.info > p');
    if (statusEl != null) {
      manga.status = parseStatus(statusEl.text);
    }

    // Extract manga ID from URL (after last dot: /manga/one-piece.rj2y -> rj2y)
    final mangaId = fullUrl.split('.').last.split('/').first;

    // Fetch chapters via AJAX
    final chapters = <MChapter>[];
    try {
      final ajaxUrl = '$baseUrl/ajax/manga/$mangaId/chapter/en';
      final ajaxRes = await client.get(ajaxUrl, headers: {
        'Referer': fullUrl,
        'X-Requested-With': 'XMLHttpRequest',
      });

      // Response is JSON: {"result":"<html>","status":200}
      // Use native jsonDecode to properly unescape the HTML
      final jsonData = jsonDecode(ajaxRes.body);
      final html = jsonData['result'] ?? ajaxRes.body;

      final chDoc = Document(html);
      final chEls = chDoc.select('li');
      for (final li in chEls) {
        final a = li.selectFirst('a');
        if (a == null) {
          continue;
        }

        final href = a.attr('href');
        if (href == null || href.isEmpty) {
          continue;
        }

        final ch = MChapter();
        if (href.startsWith('http')) {
          ch.url = href;
        } else {
          ch.url = '$baseUrl$href';
        }

        // Name from first span, date from second span
        final spans = li.select('span');
        if (spans.isNotEmpty) {
          ch.name = spans[0].text.trim();
          if (spans.length > 1) {
            ch.dateUpload = spans[1].text.trim();
          }
        } else {
          ch.name = a.text.trim();
        }

        if (ch.name == null || ch.name!.isEmpty) {
          ch.name = 'Chapter';
        }

        chapters.add(ch);
      }
    } catch (e) {
      // Chapter fetch failed
    }

    manga.chapters = chapters;
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: _headers);
    final body = res.body;
    final pages = <String>[];

    // Try AJAX endpoint first — extract chapter number from URL
    // URL format: /read/slug.id/en/chapter-123
    try {
      // Find the reading ID in the page HTML (data attribute or script)
      final chIdMatch = RegExp('data-id="(\\d+)"').firstMatch(body);
      if (chIdMatch != null) {
        final chId = chIdMatch.group(1)!;
        final ajaxUrl = '$baseUrl/ajax/read/chapter/$chId';
        final ajaxRes = await client.get(ajaxUrl, headers: {
          'Referer': fullUrl,
          'X-Requested-With': 'XMLHttpRequest',
        });
        // Response: {"result":{"images":[["url",width,offset],...]}}
        final data = jsonDecode(ajaxRes.body);
        final result = data['result'];
        if (result != null) {
          final images = result['images'];
          if (images is List) {
            for (final img in images) {
              if (img is List && img.isNotEmpty) {
                pages.add(img[0].toString());
              }
            }
          }
        }
      }
    } catch (e) {
      // AJAX failed (likely needs VRF)
    }

    // Fallback: extract static.mfcdn.nl image URLs from page source
    if (pages.isEmpty) {
      final imgPattern = RegExp("https?://static\\.mfcdn\\.nl/[^\"\\s]+\\.(?:jpg|jpeg|png|webp)");
      final cdnMatches = imgPattern.allMatches(body);
      final seen = <String>{};
      for (final m in cdnMatches) {
        final imgUrl = m.group(0)!;
        if (!seen.contains(imgUrl)) {
          seen.add(imgUrl);
          pages.add(imgUrl);
        }
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

    // Keiyoushi selector: .original.card-lg .unit .inner
    var elements = doc.select('.original .unit .inner');
    if (elements.isEmpty) elements = doc.select('.unit .inner');
    if (elements.isEmpty) elements = doc.select('.original .unit');

    for (final el in elements) {
      final manga = MManga();

      // Link and title from .info > a
      final infoLink = el.selectFirst('.info a');
      if (infoLink != null) {
        var href = infoLink.attr('href') ?? '';
        if (href.isNotEmpty && !href.startsWith('http')) href = '$baseUrl$href';
        manga.link = href;
        manga.name = infoLink.text.trim();
      }

      // Fallback: link from parent or any a tag
      if (manga.link == null || manga.link!.isEmpty) {
        final a = el.selectFirst('a[href]');
        if (a != null) {
          var href = a.attr('href') ?? '';
          if (href.isNotEmpty && !href.startsWith('http')) href = '$baseUrl$href';
          manga.link = href;
          if (manga.name == null || manga.name!.isEmpty) manga.name = a.attr('title') ?? a.text.trim();
        }
      }

      // Image
      final imgEl = el.selectFirst('img[src]');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();

      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) {
        mangaList.add(manga);
      }
    }

    // Pagination: .page-item.active + .page-item .page-link
    final nextPage = doc.selectFirst('.page-item.active + .page-item .page-link');
    return MPages(mangaList, nextPage != null);
  }
}

MangaFire main(MSource source) {
  return MangaFire(source: source);
}
