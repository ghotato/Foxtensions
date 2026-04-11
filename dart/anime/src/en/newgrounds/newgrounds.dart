// Newgrounds - Flash/HTML5 animation and video portal

import 'package:foxlations/bridge_lib.dart';

class Newgrounds extends MProvider {
  Newgrounds({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://www.newgrounds.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
        'X-Requested-With': 'XMLHttpRequest',
      };

  // ── Browse ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/movies/?sort=score&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/movies/?sort=date&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get(
        '$baseUrl/search/conduct/movies?terms=$q&page=$page',
        headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.item-portalsubmission, .portal-item, .item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a.item-link, a');
      final img = item.querySelector('img');
      final title = item.querySelector('.detail-title, h4, .title');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      // Only include portal/view submissions (movies/animations)
      if (!href.contains('/portal/view/') && !href.contains('newgrounds.com/portal/view')) continue;
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? img?.attr('alt') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('data-src') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty) list.add(m);
    }
    return MPages(list, list.length >= 20);
  }

  // ── Detail ───────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('#portal-submission-title, h2.pod-head, h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ?? '';
    manga.description = doc.querySelector('#author-comments .body-text, .pod-body p')?.text.trim()
        ?? doc.querySelector('meta[name="description"]')?.attr('content') ?? '';

    final tags = doc.querySelectorAll('.tags a, .tag-cloud a');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    final chapter = MChapter();
    chapter.name = 'Watch';
    chapter.url = url;
    manga.chapters = [chapter];

    return manga;
  }

  // ── Video extraction ─────────────────────────────────────────────────────

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final List<MVideo> videos = [];

    // Newgrounds stores sources in JSON: "sources":[{"src":"url","type":"video/mp4","label":"1080p"}]
    final sourcesMatch = RegExp('"sources":\\s*\\[([^\\]]+)\\]').firstMatch(html);
    if (sourcesMatch != null) {
      try {
        final sourcesJson = '[${sourcesMatch.group(1)!}]';
        final sources = jsonDecode(sourcesJson) as List;
        for (final src in sources) {
          final srcUrl = src['src']?.toString() ?? '';
          final label = src['label']?.toString() ?? 'Source';
          if (srcUrl.isEmpty) continue;
          final video = MVideo();
          video.url = srcUrl;
          video.quality = label;
          video.originalUrl = srcUrl;
          video.headers = _headers;
          videos.add(video);
        }
      } catch (_) {}
    }

    // Also check for single "src":"url" pattern in player config
    if (videos.isEmpty) {
      final srcMatch = RegExp('"src":\\s*"(https?://[^"]+\\.(mp4|m3u8)[^"]*)"').firstMatch(html);
      if (srcMatch != null) {
        final u = srcMatch.group(1)!;
        final video = MVideo();
        video.url = u;
        video.quality = u.contains('.m3u8') ? 'HLS' : 'MP4';
        video.originalUrl = u;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // Fallback: scan for direct mp4/m3u8 URLs
    if (videos.isEmpty) {
      var remaining = html;
      final urlPat = RegExp('https?://[^"\'\\s]+\\.(mp4|m3u8)[^"\'\\s]*');
      var m = urlPat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = u.contains('.m3u8') ? 'HLS' : 'MP4';
          video.originalUrl = u;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(m.end);
        m = urlPat.firstMatch(remaining);
      }
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

Newgrounds main(MSource source) => Newgrounds(source: source);
