// oppaistream.com - Hentai anime streaming

import 'package:foxlations/bridge_lib.dart';

class OppaiStream extends MProvider {
  OppaiStream({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://oppaistream.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  // ── Browse ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/hentai?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/?s=$q&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.video-item, article, .item, .post');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('h2, h3, .title, .video-title');
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
    manga.imageUrl = doc.querySelector('.poster img, .thumbnail img, .cover img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.description p, .synopsis, .content p')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.genres a, .tags a, .genre');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    final episodes = doc.querySelectorAll('.episode-list a, .episodes a, .ep-list a');
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

    // JW Player / Video.js: file: "url.m3u8" or file: 'url.m3u8'
    final fileDQ = RegExp("file:\\s*\"([^\"]+\\.m3u8[^\"]*)\"");
    final fileSQ = RegExp("file:\\s*'([^']+\\.m3u8[^']*)'");
    var remaining = html;
    var fm = fileDQ.firstMatch(remaining);
    while (fm != null) {
      final u = fm.group(1)!;
      if (u.isNotEmpty) {
        final video = MVideo();
        video.url = u;
        video.quality = 'HLS';
        video.originalUrl = u;
        video.headers = _headers;
        videos.add(video);
      }
      remaining = remaining.substring(fm.end);
      fm = fileDQ.firstMatch(remaining);
    }
    if (videos.isEmpty) {
      remaining = html;
      fm = fileSQ.firstMatch(remaining);
      while (fm != null) {
        final u = fm.group(1)!;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'HLS';
          video.originalUrl = u;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(fm.end);
        fm = fileSQ.firstMatch(remaining);
      }
    }

    // Fallback: raw m3u8 scan
    if (videos.isEmpty) {
      remaining = html;
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

OppaiStream main(MSource source) => OppaiStream(source: source);
