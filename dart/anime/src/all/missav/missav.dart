// missav.com - JAV streaming with m3u8 streams

import 'package:foxlations/bridge_lib.dart';

class MissAV extends MProvider {
  MissAV({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://missav.ai';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$baseUrl/',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cookie': 'locale=en; cf_clearance=; age_confirmed=1',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/en/monthly-hot?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('https://missav.ai/dm515/en/new?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/en/search?query=$q&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  Future<MPages> _parseList(String html) async {
    final doc = parseHtml(html);
    // MissAV uses div.thumbnail as the item container
    var items = doc.querySelectorAll('div.thumbnail');
    // Fallback selectors if structure differs
    if (items.isEmpty) {
      items = doc.querySelectorAll('.group, article, .video-item');
    }
    final list = <MManga>[];
    for (final item in items) {
      // Primary link is a.text-secondary (title link); fall back to first anchor
      final titleAnchor = item.querySelector('a.text-secondary');
      final a = titleAnchor ?? item.querySelector('a');
      final img = item.querySelector('img');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      if (href.isEmpty || href == '/') continue;
      final m = MManga();
      m.name = titleAnchor?.text.trim() ??
          item.querySelector('p.truncate')?.text.trim() ??
          img?.attr('alt') ??
          a.attr('title') ??
          'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      // Both video[data-poster] and img[data-src] point to fourhoi.com (Cloudflare
      // Managed Challenge). Store the URL but replace with javdatabase cover below.
      final video = item.querySelector('video');
      m.imageUrl = video?.attr('data-poster')
          ?? img?.attr('data-src')
          ?? img?.attr('src')
          ?? '';
      if (m.link.isNotEmpty && m.link != baseUrl) list.add(m);
    }
    // Detect next page via pagination link
    final hasNext = doc.querySelector('a[rel="next"], .pagination .next, nav[aria-label*="pagination"] a[aria-label*="Next"]') != null
        || list.length >= 24;

    // Fetch alternative covers from javdatabase.com in parallel.
    // fourhoi.com (MissAV's image CDN) is behind Cloudflare Managed Challenge
    // and can't be loaded without a real browser session.
    await Future.wait(list.map((m) async {
      final slug = Uri.tryParse(m.link)?.pathSegments.last ?? '';
      final code = _javCode(slug);
      if (code == null) return;
      final alt = await _javDbCover(code);
      if (alt.isNotEmpty) m.imageUrl = alt;
    }));

    return MPages(list, hasNext);
  }

  /// Extracts JAV code from a URL slug.
  /// e.g. 'miaa-329-uncensored-leak' → 'MIAA-329'
  String? _javCode(String slug) {
    final m = RegExp(r'^([a-zA-Z]+-\d+)', caseSensitive: false).firstMatch(slug);
    if (m == null) return null;
    return m.group(1)!.toUpperCase();
  }

  /// Fetches cover art from javdatabase.com for the given JAV code.
  /// Returns the og:image URL, or empty string on failure.
  Future<String> _javDbCover(String code) async {
    try {
      final res = await client.get(
        'https://www.javdatabase.com/movies/${code.toLowerCase()}/',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      if (res.statusCode != 200) return '';
      final doc = parseHtml(res.body);
      return doc.querySelector('meta[property="og:image"]')?.attr('content') ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h1.text-base, h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ?? '';
    manga.description = doc.querySelector('meta[name="description"]')?.attr('content') ?? '';

    final tags = doc.querySelectorAll('.space-x-1 a, .genre-tag a, .tag a');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    final chapter = MChapter();
    chapter.name = 'Watch';
    chapter.url = url;
    manga.chapters = [chapter];

    return manga;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final List<MVideo> videos = [];

    // MissAV embeds the stream URL in a P.A.C.K.E.R.-encoded script block.
    // Approach (per Kohi-den): find the packed script, unpack it, then extract
    // source="<masterPlaylistUrl>" from the decoded output.

    // Step 1: Try unpacking P.A.C.K.E.R. block.
    final evalMatch = RegExp(r'eval\(function\(p,a,c,k,e,d\)').firstMatch(html);
    if (evalMatch != null) {
      final packed = html.substring(evalMatch.start);
      final unpacked = _unpackPacker(packed.substring(0, packed.length.clamp(0, 8000)));
      final srcMatch = RegExp(r'''source=["']([^"']+\.m3u8[^"']*)["']''').firstMatch(unpacked)
          ?? RegExp(r'''source=["']([^"']+)["']''').firstMatch(unpacked);
      if (srcMatch != null) {
        final masterUrl = srcMatch.group(1)!;
        // Fetch the master playlist and extract quality variants.
        final qualities = await _extractHlsQualities(masterUrl);
        if (qualities.isNotEmpty) {
          videos.addAll(qualities);
        } else {
          // Master playlist fetch failed; use URL directly.
          final video = MVideo();
          video.url = masterUrl;
          video.quality = 'HLS';
          video.originalUrl = masterUrl;
          video.headers = _headers;
          videos.add(video);
        }
      }
    }

    // Step 2: Direct source= assignment or bare m3u8 in raw HTML (fast path).
    if (videos.isEmpty) {
      final srcMatch = RegExp(r'''source\s*=\s*["']([^"']+\.m3u8[^"']*)["']''').firstMatch(html);
      if (srcMatch != null) {
        final video = MVideo();
        video.url = srcMatch.group(1)!;
        video.quality = 'HLS';
        video.originalUrl = srcMatch.group(1)!;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // Step 3: WebView capture as last resort (handles any future obfuscation).
    if (videos.isEmpty) {
      final webView = WebView();
      final captured = await webView.captureRequest(url, '.m3u8', timeout: 25);
      if (captured != null && captured.isNotEmpty) {
        final video = MVideo();
        video.url = captured;
        video.quality = 'HLS';
        video.originalUrl = captured;
        video.headers = _headers;
        videos.add(video);
      }
    }

    return videos;
  }

  /// Fetch an HLS master playlist and return one MVideo per quality variant.
  Future<List<MVideo>> _extractHlsQualities(String masterUrl) async {
    try {
      final res = await client.get(masterUrl, headers: _headers);
      if (res.body.isEmpty) return [];
      final lines = res.body.split('\n');
      final result = <MVideo>[];
      for (var i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
        final nextLine = lines[i + 1].trim();
        if (nextLine.isEmpty || nextLine.startsWith('#')) continue;
        // Extract RESOLUTION=WxH or BANDWIDTH for quality label.
        final res2 = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
        final height = res2?.group(1) ?? '';
        final bandwidth = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '';
        final label = height.isNotEmpty ? '${height}p' : (bandwidth.isNotEmpty ? '${(int.tryParse(bandwidth) ?? 0) ~/ 1000}kbps' : 'HLS');
        final segUrl = nextLine.startsWith('http') ? nextLine : Uri.parse(masterUrl).resolve(nextLine).toString();
        final video = MVideo();
        video.url = segUrl;
        video.quality = label;
        video.originalUrl = segUrl;
        video.headers = _headers;
        result.add(video);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// P.A.C.K.E.R deobfuscator — decodes eval(function(p,a,c,k,e,d){...}(...))
  String _unpackPacker(String packed) {
    final argsMatch = RegExp(r"\}\('([^']+)',(\d+),(\d+),'([^']+)'").firstMatch(packed);
    if (argsMatch == null) return packed;
    final p = argsMatch.group(1)!;
    final a = int.parse(argsMatch.group(2)!);
    final k = argsMatch.group(4)!.split('|');

    String decodeToken(String word) {
      var n = 0;
      for (var i = 0; i < word.length; i++) {
        final ch = word[i];
        int digit;
        if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
          digit = ch.codeUnitAt(0) - '0'.codeUnitAt(0);
        } else if (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) {
          digit = ch.codeUnitAt(0) - 'a'.codeUnitAt(0) + 10;
        } else if (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) {
          digit = ch.codeUnitAt(0) - 'A'.codeUnitAt(0) + 36;
        } else {
          digit = 0;
        }
        n = n * a + digit;
      }
      return (n < k.length && k[n].isNotEmpty) ? k[n] : word;
    }

    var result = '';
    var remaining = p;
    final wordPat = RegExp(r'\b\w+\b');
    var wm = wordPat.firstMatch(remaining);
    while (wm != null) {
      result += remaining.substring(0, wm.start) + decodeToken(wm.group(0)!);
      remaining = remaining.substring(wm.end);
      wm = wordPat.firstMatch(remaining);
    }
    return result + remaining;
  }

  @override
  List<dynamic> getFilterList() => [];
}

MissAV main(MSource source) => MissAV(source: source);
