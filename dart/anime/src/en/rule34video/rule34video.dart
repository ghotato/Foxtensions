// rule34video.com - Adult animated video site
// Uses their search page + video embed scraping

import 'package:foxlations/bridge_lib.dart';

class Rule34Video extends MProvider {
  Rule34Video({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://rule34video.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get(
        '$baseUrl/videos/?mode=async&function=get_block&block_id=list_videos_common_videos_list&sort_by=most_viewed&period=alltime&from=${(page - 1) * 30}',
        headers: _headers);
    return _parseList(res.body, page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get(
        '$baseUrl/videos/?mode=async&function=get_block&block_id=list_videos_common_videos_list&sort_by=post_date&from=${(page - 1) * 30}',
        headers: _headers);
    return _parseList(res.body, page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get(
        '$baseUrl/videos/?mode=async&function=get_block&block_id=list_videos_common_videos_list&sort_by=post_date&search_query=$q&from=${(page - 1) * 30}',
        headers: _headers);
    return _parseList(res.body, page);
  }

  MPages _parseList(String html, int page) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.item, .video-item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a.th, a');
      final img = item.querySelector('img');
      final title = item.querySelector('.info a, .title a, .item-title');
      if (a == null) continue;
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? 'Unknown';
      m.link = a.attr('href') ?? '';
      if (!m.link.startsWith('http')) m.link = '$baseUrl${m.link}';
      m.imageUrl = img?.attr('data-original') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty && m.name != 'Unknown') list.add(m);
    }
    return MPages(list, list.length >= 28);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h1.title, .video-title h1, h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('video[poster], #main-video[poster]')?.attr('poster') ?? '';
    manga.description = doc.querySelector('.description p, .info .desc')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.tag-list a, .tags a');
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

    // Rule34video encodes sources in a sources array: "src":"url","label":"1080p"
    final srcPat = RegExp('"src":"(https?://[^"]+)"');
    final qualPat = RegExp('"label":"([^"]+)"');

    var remaining = html;
    var srcMatch = srcPat.firstMatch(remaining);
    while (srcMatch != null) {
      final srcUrl = srcMatch.group(1)!;
      // Try to find associated label right after or before this match
      final window = remaining.substring(
          (srcMatch.start - 100).clamp(0, remaining.length),
          (srcMatch.end + 100).clamp(0, remaining.length));
      final qualMatch = qualPat.firstMatch(window);
      final quality = qualMatch?.group(1) ?? 'Default';

      final video = MVideo();
      video.url = srcUrl;
      video.quality = quality;
      video.originalUrl = srcUrl;
      video.headers = _headers;
      videos.add(video);

      remaining = remaining.substring(srcMatch.end);
      srcMatch = srcPat.firstMatch(remaining);
    }

    // Fallback: scan for direct mp4 links
    if (videos.isEmpty) {
      remaining = html;
      final mp4Pat = RegExp('https?://\\S+\\.mp4');
      var m = mp4Pat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        final video = MVideo();
        video.url = u;
        video.quality = 'MP4';
        video.originalUrl = u;
        video.headers = _headers;
        videos.add(video);
        remaining = remaining.substring(m.end);
        m = mp4Pat.firstMatch(remaining);
      }
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

Rule34Video main(MSource source) => Rule34Video(source: source);
