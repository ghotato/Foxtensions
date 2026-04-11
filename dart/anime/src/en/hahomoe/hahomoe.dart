// haho.moe - Hentai anime streaming

import 'package:foxlations/bridge_lib.dart';

class HaHoMoe extends MProvider {
  HaHoMoe({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://haho.moe';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/anime?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/anime?sort=latest&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/anime?search=$q&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.card, .anime-card, .product-item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('.title, h3, h4, .card-title');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? 'Unknown';
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
    manga.name = doc.querySelector('h1, h2.title')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('.cover img, .poster img, img.cover')?.attr('src') ?? '';
    manga.description = doc.querySelector('.description, .synopsis, .summary')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.genre a, .tags a, .tag');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    final episodes = doc.querySelectorAll('.ep-list a, .episode-list a, .episodes a');
    final chapters = <MChapter>[];
    for (final ep in episodes) {
      final chapter = MChapter();
      chapter.name = ep.text.trim().isEmpty ? 'Episode' : ep.text.trim();
      chapter.url = ep.attr('href') ?? '';
      if (chapter.url.isNotEmpty && !chapter.url.startsWith('http')) {
        chapter.url = '$baseUrl${chapter.url}';
      }
      if (chapter.url.isNotEmpty) chapters.add(chapter);
    }
    if (chapters.isEmpty) {
      final chapter = MChapter();
      chapter.name = 'Watch';
      chapter.url = url;
      chapters.add(chapter);
    }
    manga.chapters = chapters.reversed.toList();

    return manga;
  }

  // ── Video extraction ─────────────────────────────────────────────────────

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final List<MVideo> videos = [];

    // Check for iframe embed and follow it
    final doc = parseHtml(html);
    final iframe = doc.querySelector('iframe[src*="embed"], iframe[src*="player"]');
    if (iframe != null) {
      final embedSrc = iframe.attr('src') ?? '';
      if (embedSrc.isNotEmpty) {
        final embedUrl = embedSrc.startsWith('http') ? embedSrc : '$baseUrl$embedSrc';
        try {
          final embedRes = await client.get(embedUrl, headers: {
            'Referer': '$baseUrl/',
            'User-Agent': _headers['User-Agent']!,
          });
          var remaining = embedRes.body;
          final hlsPat = RegExp('https?://\\S+\\.m3u8');
          var m = hlsPat.firstMatch(remaining);
          while (m != null) {
            final u = m.group(0)!.split('"').first.split("'").first;
            if (u.isNotEmpty) {
              final video = MVideo();
              video.url = u;
              video.quality = 'HLS';
              video.originalUrl = u;
              video.headers = {'Referer': embedUrl, 'User-Agent': _headers['User-Agent']!};
              videos.add(video);
            }
            remaining = remaining.substring(m.end);
            m = hlsPat.firstMatch(remaining);
          }
        } catch (_) {}
      }
    }

    // Fallback: JW Player / Video.js file: "url.m3u8" pattern
    if (videos.isEmpty) {
      final fileDQ = RegExp("file:\\s*\"([^\"]+\\.m3u8[^\"]*)\"");
      final fileSQ = RegExp("file:\\s*'([^']+\\.m3u8[^']*)'");
      final fileMatch = fileDQ.firstMatch(html) ?? fileSQ.firstMatch(html);
      if (fileMatch != null) {
        final video = MVideo();
        video.url = fileMatch.group(1)!;
        video.quality = 'HLS';
        video.originalUrl = fileMatch.group(1)!;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // Fallback: raw m3u8 scan
    if (videos.isEmpty) {
      var remaining = html;
      final hlsPat = RegExp('https?://\\S+\\.m3u8');
      var m = hlsPat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'HLS';
          video.originalUrl = u;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(m.end);
        m = hlsPat.firstMatch(remaining);
      }
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

HaHoMoe main(MSource source) => HaHoMoe(source: source);
