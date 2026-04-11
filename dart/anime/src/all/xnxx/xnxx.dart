// xnxx.com - Adult video site

import 'package:foxlations/bridge_lib.dart';

class Xnxx extends MProvider {
  Xnxx({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://www.xnxx.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/search/all/${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/new-videos/${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = query.trim().replaceAll(' ', '+');
    final res = await client.get('$baseUrl/search/$q/${page - 1}', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.mozaique .thumb-block, #content .thumb');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a');
      final img = item.querySelector('img');
      final title = item.querySelector('p.title');
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
    manga.name = doc.querySelector('h2, .clear-infobar strong')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ?? '';

    final tags = doc.querySelectorAll('.video-tags a, .tags a');
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

    // xnxx uses html5player.setVideoHLS and setVideoUrl* calls
    final hlsMatch = RegExp("setVideoHLS\\('([^']+)'\\)").firstMatch(html);
    if (hlsMatch != null) {
      final video = MVideo();
      video.url = hlsMatch.group(1)!;
      video.quality = 'HLS';
      video.originalUrl = hlsMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

    final highMatch = RegExp("setVideoUrlHigh\\('([^']+)'\\)").firstMatch(html);
    if (highMatch != null) {
      final video = MVideo();
      video.url = highMatch.group(1)!;
      video.quality = 'HD';
      video.originalUrl = highMatch.group(1)!;
      video.headers = _headers;
      videos.add(video);
    }

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

Xnxx main(MSource source) => Xnxx(source: source);
