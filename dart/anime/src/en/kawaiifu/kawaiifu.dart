// kawaiifu.com - Hentai anime streaming

import 'package:foxlations/bridge_lib.dart';

class Kawaiifu extends MProvider {
  Kawaiifu({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://kawaiifu.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/most-view/?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/?page=$page', headers: _headers);
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
    final items = doc.querySelectorAll('.item, article.item, .post');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('.info h4, h4 a, h3 a, .title');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('src') ?? img?.attr('data-src') ?? '';
      if (m.link.isNotEmpty && m.link != baseUrl) list.add(m);
    }
    return MPages(list, list.length >= 12);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h2.title, h1.title, h1, h2')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('.img img, .thumb img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.desc p, .description, .summary-content')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.tag a, .tags a, .genre a');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    // Episode list
    final episodes = doc.querySelectorAll('.ep-item a, .list-ep a, ul.server-list li a');
    final chapters = <MChapter>[];
    for (final ep in episodes) {
      final chapter = MChapter();
      chapter.name = ep.text.trim().isEmpty ? 'Episode' : ep.text.trim();
      chapter.url = ep.attr('href') ?? '';
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

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final List<MVideo> videos = [];

    // Kawaiifu embeds via iframe — look for src in server list
    final iframeSrc = RegExp('file:\\s*"([^"]+\\.m3u8[^"]*)"').firstMatch(html)
        ?? RegExp("file:\\s*'([^']+\\.m3u8[^']*)'").firstMatch(html);
    if (iframeSrc != null) {
      final video = MVideo();
      video.url = iframeSrc.group(1)!;
      video.quality = 'HLS';
      video.originalUrl = iframeSrc.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

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

Kawaiifu main(MSource source) => Kawaiifu(source: source);
