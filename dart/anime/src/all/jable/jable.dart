// jable.tv - JAV streaming site

import 'package:foxlations/bridge_lib.dart';

class Jable extends MProvider {
  Jable({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://jable.tv';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/hot/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/new-release/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/search/$q/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.video-img-box, .list-item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('.detail .title, h6 a, .title');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? img?.attr('alt') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('data-src') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty && m.link != baseUrl) list.add(m);
    }
    return MPages(list, list.length >= 20);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h2.title, h1.title, h2, h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ??
        doc.querySelector('.video-cover img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.video-info .desc, .description')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.tags a, .label-tag a');
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

    // Jable embeds m3u8 via a variable: var hlsUrl = '...'
    final hlsMatch = RegExp("hlsUrl\\s*=\\s*'([^']+)'").firstMatch(html)
        ?? RegExp('hlsUrl\\s*=\\s*"([^"]+)"').firstMatch(html);
    if (hlsMatch != null) {
      final video = MVideo();
      video.url = hlsMatch.group(1)!;
      video.quality = 'HLS';
      video.originalUrl = hlsMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

    // Fallback: scan for m3u8
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

Jable main(MSource source) => Jable(source: source);
