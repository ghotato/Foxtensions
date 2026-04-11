// supjav.com - JAV streaming

import 'package:foxlations/bridge_lib.dart';

class SupJAV extends MProvider {
  SupJAV({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://supjav.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  // ── Browse ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/popular/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/page/$page/', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/?s=$q&paged=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.post-item, article, .item-post, .videos-item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('.post-title, h2, h3, .title');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? img?.attr('alt') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('data-src') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty && m.link != baseUrl) list.add(m);
    }
    return MPages(list, list.length >= 12);
  }

  // ── Detail ───────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h1.post-title, h1, h2')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content')
        ?? doc.querySelector('.post-thumbnail img, .featured-image img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.post-content p, .description')?.text.trim()
        ?? doc.querySelector('meta[name="description"]')?.attr('content') ?? '';

    final tags = doc.querySelectorAll('.tags a, .post-tags a, .tag');
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

    // SupJAV: look for m3u8 URLs in script JSON
    var remaining = html;
    final m3u8Pat = RegExp('"(https?://[^"]+\\.m3u8[^"]*)"');
    var m = m3u8Pat.firstMatch(remaining);
    while (m != null) {
      final u = m.group(1)!;
      if (u.isNotEmpty) {
        final video = MVideo();
        video.url = u;
        video.quality = 'HLS';
        video.originalUrl = u;
        video.headers = _headers;
        videos.add(video);
      }
      remaining = remaining.substring(m.end);
      m = m3u8Pat.firstMatch(remaining);
    }

    // Follow iframes for external player embeds
    if (videos.isEmpty) {
      final doc = parseHtml(html);
      final iframes = doc.querySelectorAll('iframe[src]');
      for (final iframe in iframes) {
        final src = iframe.attr('src') ?? '';
        if (src.isEmpty || src.contains('ad') || src.contains('banner')) continue;
        try {
          final embedUrl = src.startsWith('http') ? src : '$baseUrl$src';
          final embedRes = await client.get(embedUrl, headers: {
            'Referer': url,
            'User-Agent': _headers['User-Agent']!,
          });
          var embedRemaining = embedRes.body;
          final hlsPat = RegExp('https?://\\S+\\.m3u8');
          var em = hlsPat.firstMatch(embedRemaining);
          while (em != null) {
            final u = em.group(0)!.split('"').first.split("'").first;
            if (u.isNotEmpty) {
              final video = MVideo();
              video.url = u;
              video.quality = 'HLS';
              video.originalUrl = u;
              video.headers = {'Referer': embedUrl, 'User-Agent': _headers['User-Agent']!};
              videos.add(video);
            }
            embedRemaining = embedRemaining.substring(em.end);
            em = hlsPat.firstMatch(embedRemaining);
          }
        } catch (_) {}
        if (videos.isNotEmpty) break;
      }
    }

    // Fallback: mp4 scan
    if (videos.isEmpty) {
      remaining = html;
      final mp4Pat = RegExp('https?://[^"\'\\s]+\\.mp4[^"\'\\s]*');
      var em = mp4Pat.firstMatch(remaining);
      while (em != null) {
        final u = em.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'MP4';
          video.originalUrl = u;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(em.end);
        em = mp4Pat.firstMatch(remaining);
      }
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

SupJAV main(MSource source) => SupJAV(source: source);
