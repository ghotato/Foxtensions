// xvideos.com - Adult video site
// Scrapes search pages and extracts HLS/MP4 from video page source

import 'package:foxlations/bridge_lib.dart';

class Xvideos extends MProvider {
  Xvideos({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://www.xvideos.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/new/${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/new/${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/?k=$q&p=${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.thumb-block, .mozaique .thumb');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('p.title a, .thumb-under p a');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      if (!href.contains('/video')) continue;
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('data-src') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty) list.add(m);
    }
    return MPages(list, list.length >= 20);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h2.page-title, #video-title, h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ?? '';
    manga.description = '';

    final tags = doc.querySelectorAll('.video-tags-list a, .tags a');
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

    // Extract HLS stream (best quality)
    final hlsMatch = RegExp("setVideoHLS\\('([^']+)'\\)").firstMatch(html);
    if (hlsMatch != null) {
      final video = MVideo();
      video.url = hlsMatch.group(1)!;
      video.quality = 'HLS';
      video.originalUrl = hlsMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

    // Extract high MP4
    final highMatch = RegExp("setVideoUrlHigh\\('([^']+)'\\)").firstMatch(html);
    if (highMatch != null) {
      final video = MVideo();
      video.url = highMatch.group(1)!;
      video.quality = 'HD';
      video.originalUrl = highMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

    // Extract low MP4
    final lowMatch = RegExp("setVideoUrlLow\\('([^']+)'\\)").firstMatch(html);
    if (lowMatch != null) {
      final video = MVideo();
      video.url = lowMatch.group(1)!;
      video.quality = 'SD';
      video.originalUrl = lowMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

Xvideos main(MSource source) => Xvideos(source: source);
