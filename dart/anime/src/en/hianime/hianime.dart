// HiAnime (hianime.to, formerly Zoro) - most popular anime streaming site
// Uses AJAX API for episode lists and sources

import 'package:foxlations/bridge_lib.dart';

class HiAnime extends MProvider {
  HiAnime({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://hianime.to';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
        'X-Requested-With': 'XMLHttpRequest',
      };

  // ── Browse ───────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get('$baseUrl/most-popular?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get('$baseUrl/recently-updated?page=$page', headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/search?keyword=$q&page=$page', headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final items = doc.querySelectorAll('.flw-item, .film_list-wrap .flw-item');
    final list = <MManga>[];
    for (final item in items) {
      final a = item.querySelector('a.film-poster-ahref, a');
      final img = item.querySelector('img.film-poster-img, img');
      final title = item.querySelector('.film-detail .film-name a, .film-name');
      if (a == null) continue;
      final href = a.attr('href') ?? '';
      final m = MManga();
      m.name = title?.text.trim() ?? a.attr('title') ?? 'Unknown';
      m.link = href.startsWith('http') ? href : '$baseUrl$href';
      m.imageUrl = img?.attr('data-src') ?? img?.attr('src') ?? '';
      if (m.link.isNotEmpty && m.link != baseUrl) list.add(m);
    }
    final hasNext = parseHtml(html).querySelector('.pagination .page-item:last-child:not(.disabled)') != null;
    return MPages(list, hasNext);
  }

  // ── Detail ───────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final doc = parseHtml(html);

    final manga = MManga();
    manga.name = doc.querySelector('h2.film-name, .anisc-detail .film-name')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('.film-poster img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.film-description .text, .anisc-detail .film-description')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.item-list a[href*="genre"], .anisc-detail .item-list a');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    // Extract anime ID from URL (last segment before ?)
    final animeId = _extractAnimeId(url);
    if (animeId.isNotEmpty) {
      manga.chapters = await _fetchEpisodes(animeId);
    }

    return manga;
  }

  String _extractAnimeId(String url) {
    // URL: https://hianime.to/watch/one-piece-100?ep=2142  or
    //       https://hianime.to/one-piece-100
    final path = Uri.parse(url).path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    final last = segments.last;
    // ID is the trailing number after the last dash
    final match = RegExp(r'-(\d+)$').firstMatch(last);
    return match?.group(1) ?? last;
  }

  Future<List<MChapter>> _fetchEpisodes(String animeId) async {
    final res = await client.get(
        '$baseUrl/ajax/v2/episode/list/$animeId',
        headers: _headers);
    final data = jsonDecode(res.body);
    final html = data['html']?.toString() ?? '';
    final doc = parseHtml(html);

    final eps = doc.querySelectorAll('.ss-list a[data-id], .ss-list .ep-item');
    final chapters = <MChapter>[];
    for (final ep in eps) {
      final epId = ep.attr('data-id') ?? ep.attr('data-number') ?? '';
      final epNum = ep.attr('data-number') ?? ep.attr('title') ?? '';
      final epTitle = ep.attr('title') ?? 'Episode $epNum';
      if (epId.isEmpty) continue;
      final chapter = MChapter();
      chapter.name = epTitle;
      chapter.url = '$baseUrl/watch?ep=$epId';
      chapters.add(chapter);
    }
    return chapters.reversed.toList();
  }

  // ── Video extraction ─────────────────────────────────────────────────────

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    // Extract episode ID from URL
    final epId = Uri.parse(url).queryParameters['ep'] ?? '';
    if (epId.isEmpty) return [];

    // Get available servers for this episode
    final res = await client.get(
        '$baseUrl/ajax/v2/episode/servers?episodeId=$epId',
        headers: _headers);
    final data = jsonDecode(res.body);
    final html = data['html']?.toString() ?? '';
    final doc = parseHtml(html);

    final List<MVideo> videos = [];
    final servers = doc.querySelectorAll('.server-item, [data-server-id]');

    for (final server in servers) {
      final serverId = server.attr('data-id') ?? server.attr('data-server-id') ?? '';
      final serverName = server.text.trim();
      final type = server.attr('data-type') ?? 'sub'; // sub or dub
      if (serverId.isEmpty) continue;

      try {
        final srcRes = await client.get(
            '$baseUrl/ajax/v2/episode/sources?id=$serverId',
            headers: _headers);
        final srcData = jsonDecode(srcRes.body);
        final embedUrl = srcData['link']?.toString() ?? '';
        if (embedUrl.isEmpty) continue;

        // Try to extract m3u8 directly from the embed page
        final embedRes = await client.get(embedUrl, headers: {
          'Referer': '$baseUrl/',
          'User-Agent': _headers['User-Agent']!,
        });
        final embedHtml = embedRes.body;

        var remaining = embedHtml;
        final hlsPat = RegExp('https?://\\S+\\.m3u8');
        var m = hlsPat.firstMatch(remaining);
        while (m != null) {
          final u = m.group(0)!.split('"').first.split("'").first;
          if (u.isNotEmpty) {
            final video = MVideo();
            video.url = u;
            video.quality = '$serverName ($type)';
            video.originalUrl = embedUrl;
            video.headers = {'Referer': embedUrl, 'User-Agent': _headers['User-Agent']!};
            videos.add(video);
          }
          remaining = remaining.substring(m.end);
          m = hlsPat.firstMatch(remaining);
        }
      } catch (_) {}
    }

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

HiAnime main(MSource source) => HiAnime(source: source);
