// Hitomi.la — uses the ltn.hitomi.la JS/binary API.
//
// Why the SPA approach: hitomi.la's HTML pages (index-all.html, search.html,
// galleries/{id}.html) are SPA shells that load content client-side, so
// scraping the HTML returns nothing useful. The real data lives at:
//
//   https://ltn.hitomi.la/index-all.nozomi              ← all galleries
//   https://ltn.hitomi.la/popular/today-all.nozomi      ← popular today
//   https://ltn.hitomi.la/tag/<tag>-all.nozomi          ← tag-based search
//   https://ltn.hitomi.la/galleryblock/<id>.html        ← single gallery card
//   https://ltn.hitomi.la/galleries/<id>.js             ← full metadata + files
//
// .nozomi files are sequences of 4-byte big-endian gallery IDs. We use a
// Range request to grab one page worth of IDs, then fetch a galleryblock per
// ID to populate the listing.

import 'package:foxlations/bridge_lib.dart';

class Hitomi extends MProvider {
  Hitomi({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get ltnUrl => 'https://ltn.hitomi.la';

  static const int _perPage = 25;

  @override
  Future<MPages> getPopular(int page) =>
      _fetchByNozomi('$ltnUrl/popular/today-all.nozomi', page);

  @override
  Future<MPages> getLatestUpdates(int page) =>
      _fetchByNozomi('$ltnUrl/index-all.nozomi', page);

  @override
  Future<MPages> search(String query, int page, FilterList filterList) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _fetchByNozomi('$ltnUrl/index-all.nozomi', page);
    }
    // Simple tag-based search: lowercase, spaces → underscores. Multi-tag
    // queries fall through to single-tag matching against the first token.
    final tag = trimmed.toLowerCase().replaceAll(' ', '_');
    return _fetchByNozomi('$ltnUrl/tag/$tag-all.nozomi', page);
  }

  Future<MPages> _fetchByNozomi(String nozomiUrl, int page) async {
    final start = (page - 1) * _perPage * 4;
    final end = start + (_perPage * 4) - 1;

    List<int> bytes;
    try {
      bytes = await client.getBytes(nozomiUrl, headers: {
        'Referer': '$baseUrl/',
        'Range': 'bytes=$start-$end',
      });
    } catch (_) {
      return MPages([], false);
    }

    // Parse big-endian uint32 gallery IDs out of the binary blob.
    final ids = <int>[];
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final id = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      ids.add(id);
    }

    final mangaList = <MManga>[];
    for (final id in ids) {
      try {
        final res = await client.get('$ltnUrl/galleryblock/$id.html',
            headers: {'Referer': '$baseUrl/'});
        final m = _parseGalleryBlock(res.body, id);
        if (m != null) mangaList.add(m);
      } catch (_) {
        // skip individual gallery failures so a bad ID doesn't blank the
        // whole page
      }
    }

    return MPages(mangaList, ids.length >= _perPage);
  }

  MManga? _parseGalleryBlock(String html, int id) {
    final doc = Document(html);
    final manga = MManga();

    // Title — galleryblock has it under h1.lillie a (newer) or just h1 a.
    final titleEl = doc.selectFirst('h1.lillie a, h1 a, h1');
    if (titleEl != null) manga.name = titleEl.text.trim();

    // Link — prefer the title anchor, fall back to the canonical gallery URL.
    final linkEl = doc.selectFirst('h1.lillie a, h1 a, a.dj-img1, a');
    var href = linkEl?.attr('href') ?? '/galleries/$id.html';
    manga.link = href.startsWith('http') ? href : '$baseUrl$href';

    // Cover thumbnail — lazyload uses data-src; fall back to src.
    final imgEl = doc.selectFirst('img.lazyload, picture img, img');
    if (imgEl != null) {
      var src = imgEl.attr('data-src') ?? imgEl.attr('src') ?? '';
      if (src.startsWith('//')) src = 'https:$src';
      if (src.isNotEmpty) manga.imageUrl = src;
    }

    if (manga.name == null || manga.name!.isEmpty) return null;
    return manga;
  }

  @override
  Future<MManga> getDetail(String url) async {
    final manga = MManga();
    final id = RegExp(r'(\d+)\.html').firstMatch(url)?.group(1);
    if (id == null) {
      manga.name = 'Unknown gallery';
      manga.chapters = [];
      return manga;
    }

    try {
      // Pull metadata from the .js endpoint (the same one used by getPageList).
      final jsRes = await client.get('$ltnUrl/galleries/$id.js',
          headers: {'Referer': '$baseUrl/'});
      final body = jsRes.body;

      final titleMatch =
          RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(body);
      if (titleMatch != null) {
        manga.name = titleMatch
            .group(1)!
            .replaceAll(r'\"', '"')
            .replaceAll(r'\/', '/');
      }

      final langMatch =
          RegExp(r'"language"\s*:\s*"([^"]*)"').firstMatch(body);
      final typeMatch = RegExp(r'"type"\s*:\s*"([^"]*)"').firstMatch(body);
      final dateMatch = RegExp(r'"date"\s*:\s*"([^"]*)"').firstMatch(body);
      final descParts = <String>[];
      if (typeMatch != null) descParts.add('Type: ${typeMatch.group(1)}');
      if (langMatch != null) descParts.add('Language: ${langMatch.group(1)}');
      if (dateMatch != null) descParts.add('Date: ${dateMatch.group(1)}');
      manga.description = descParts.join('\n');

      // Artists / groups become the author line.
      final authors = <String>[];
      final artistsBlock =
          RegExp(r'"artists"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
      if (artistsBlock != null) {
        for (final m
            in RegExp(r'"artist"\s*:\s*"([^"]*)"').allMatches(artistsBlock.group(1)!)) {
          authors.add(m.group(1)!.replaceAll('_', ' '));
        }
      }
      if (authors.isNotEmpty) manga.author = authors.join(', ');

      // Tags → genre list.
      final tagsBlock =
          RegExp(r'"tags"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
      if (tagsBlock != null) {
        final tags = <String>[];
        for (final m
            in RegExp(r'"tag"\s*:\s*"([^"]*)"').allMatches(tagsBlock.group(1)!)) {
          tags.add(m.group(1)!.replaceAll('_', ' '));
        }
        if (tags.isNotEmpty) manga.genre = tags;
      }

      // Cover from galleryblock — the .js file doesn't include a thumbnail URL.
      try {
        final blockRes = await client.get('$ltnUrl/galleryblock/$id.html',
            headers: {'Referer': '$baseUrl/'});
        final doc = Document(blockRes.body);
        final imgEl = doc.selectFirst('img.lazyload, picture img, img');
        if (imgEl != null) {
          var src = imgEl.attr('data-src') ?? imgEl.attr('src') ?? '';
          if (src.startsWith('//')) src = 'https:$src';
          if (src.isNotEmpty) manga.imageUrl = src;
        }
      } catch (_) {}

      // Galleries are single-chapter; reuse the gallery URL as the chapter.
      final ch = MChapter();
      ch.name = manga.name ?? 'Gallery';
      ch.url = url;
      ch.dateUpload = dateMatch?.group(1);
      manga.chapters = [ch];
    } catch (e) {
      manga.name = manga.name ?? 'Failed to load';
      manga.description = 'Hitomi metadata fetch failed: $e';
      manga.chapters = [];
    }

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final pages = <String>[];

    final galleryId = RegExp(r'(\d+)\.html').firstMatch(fullUrl)?.group(1);
    if (galleryId == null) return pages;

    try {
      final jsRes = await client.get('$ltnUrl/galleries/$galleryId.js',
          headers: {'Referer': '$baseUrl/'});
      final body = jsRes.body;

      // The files array is the source of truth for page count and hashes.
      // Split on `},{` so each entry is parsed independently.
      final filesBlock = RegExp(r'"files"\s*:\s*\[(.*?)\]', dotAll: true)
          .firstMatch(body);
      if (filesBlock != null) {
        final entries = filesBlock.group(1)!.split('},{');
        for (final entry in entries) {
          final nameMatch =
              RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(entry);
          final hashMatch =
              RegExp(r'"hash"\s*:\s*"([^"]+)"').firstMatch(entry);
          if (nameMatch == null || hashMatch == null) continue;
          pages.add(_imageUrlForHash(hashMatch.group(1)!, nameMatch.group(1)!));
        }
      }
    } catch (_) {}

    return pages;
  }

  /// Builds the CDN image URL for a gallery file.
  ///
  /// Hitomi shards images across `*a.hitomi.la` subdomains based on the last
  /// 3 hex chars of the file hash. The exact subdomain assignment is driven
  /// by gg.js which we don't fetch here — the modulo fallback works for the
  /// majority of hashes; pages that 404 will need a future gg.js parser.
  String _imageUrlForHash(String hash, String name) {
    if (hash.length < 3) {
      return 'https://aa.hitomi.la/webp/00/0/$hash.webp';
    }
    final lastHex = hash.substring(hash.length - 1);
    final lastTwoHex = hash.substring(hash.length - 3, hash.length - 1);
    final subdomain = _getSubdomain(hash);
    final ext = name.contains('.') ? name.split('.').last : 'webp';
    return 'https://${subdomain}a.hitomi.la/webp/$lastTwoHex/$lastHex/$hash.$ext';
  }

  String _getSubdomain(String hash) {
    if (hash.isEmpty) return 'a';
    final lastHex = hash.substring(hash.length - 1);
    final num = int.tryParse(lastHex, radix: 16) ?? 0;
    return String.fromCharCode('a'.codeUnitAt(0) + (num % 3));
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];
}

Hitomi main(MSource source) {
  return Hitomi(source: source);
}
