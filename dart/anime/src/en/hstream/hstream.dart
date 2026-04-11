// hstream.moe - Hentai streaming
// Scrapes the site for video data

import 'package:foxlations/bridge_lib.dart';

class Hstream extends MProvider {
  Hstream({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://hstream.moe';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/?page=$page&order=view', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/?page=$page&order=date', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/search?s=$q&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('article.entry-card, .ep-item, .video-item, article');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      if (a == null) continue;
      final m = MManga();
      m.name = a.text.trim().isNotEmpty
          ? a.text.trim()
          : (item.querySelector('.entry-title, h2, h3')?.text.trim() ?? 'Unknown');
      m.link = a.attr('href') ?? '';
      m.imageUrl = img?.attr('src') ?? img?.attr('data-src') ?? '';
      if (m.link.isNotEmpty) list.add(m);
    }
    final hasNext = parseHtml(html).querySelector('a.next, .next-page, [rel="next"]') != null;
    return MPages(list, hasNext);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h1.entry-title, h1, .post-title')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('img.attachment-post-thumbnail, .featured-image img, .poster img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.entry-content p, .description, .synopsis')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.tag-list a, .tags a, .genre a');
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

    // Scan for HLS streams using firstMatch loop (allMatches not reliable in d4rt)
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

    if (videos.isEmpty) {
      remaining = html;
      final mp4Pat = RegExp('https?://\\S+\\.mp4');
      m = mp4Pat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'MP4';
          video.originalUrl = u;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(m.end);
        m = mp4Pat.firstMatch(remaining);
      }
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

Hstream main(MSource source) => Hstream(source: source);
