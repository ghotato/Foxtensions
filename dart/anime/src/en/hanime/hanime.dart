// hanime.tv - Hentai streaming via JSON API
// API: https://hanime.tv/api/v8/

import 'package:foxlations/bridge_lib.dart';

class Hanime extends MProvider {
  Hanime({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://hanime.tv';
  String get apiUrl => 'https://hanime.tv/api/v8';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': '$baseUrl/',
      };

  String _searchBody(String query, int page) =>
      '{"search_text":"$query","tags":[],"tags_mode":"AND","brands":[],"blacklisted_tags":[],"order_by":"likes","ordering":"desc","page":${page - 1}}';

  @override
  Future<MPages> getPopular(int page) => _search('', page);

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final body =
        '{"search_text":"","tags":[],"tags_mode":"AND","brands":[],"blacklisted_tags":[],"order_by":"created_at_unix","ordering":"desc","page":${page - 1}}';
    return _doSearch(body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) =>
      _search(query, page);

  Future<MPages> _search(String query, int page) =>
      _doSearch(_searchBody(query, page));

  Future<MPages> _doSearch(String body) async {
    final res = await client.post(
      '$apiUrl/search',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: body,
    );
    final data = jsonDecode(res.body);
    final hits = (data['hits'] as List? ?? []);
    final list = hits.map((h) {
      final m = MManga();
      m.name = h['name']?.toString() ?? 'Unknown';
      m.imageUrl = h['cover_url']?.toString() ?? '';
      m.link = '$baseUrl/videos/hentai/${h['slug']}';
      return m;
    }).toList();
    return MPages(list, list.length >= 24);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final slug = url.split('/').last;
    final res = await client.get('$apiUrl/video?id=$slug', headers: _headers);
    final data = jsonDecode(res.body);
    final hv = data['hentai_video'] as Map? ?? {};

    final manga = MManga();
    manga.name = hv['name']?.toString() ?? 'Unknown';
    manga.imageUrl = hv['poster_url']?.toString() ?? '';
    manga.author = hv['brand']?.toString() ?? '';
    manga.description = hv['description']?.toString() ?? '';
    manga.genre = (hv['hentai_tags'] as List? ?? [])
        .map((t) => t['text']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    manga.status = MangaStatus.completed;

    // Each video is a single episode — use the video URL as the episode url
    final chapter = MChapter();
    chapter.name = 'Watch';
    chapter.url = url;
    manga.chapters = [chapter];

    return manga;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final slug = url.split('/').last;
    final res = await client.get('$apiUrl/video?id=$slug', headers: _headers);
    final data = jsonDecode(res.body);

    final manifests = data['videos_manifests'] as List? ?? [];
    final List<MVideo> videos = [];

    for (final manifest in manifests) {
      final streams = manifest['streams'] as List? ?? [];
      for (final s in streams) {
        final streamUrl = s['url']?.toString() ?? s['file']?.toString() ?? '';
        if (streamUrl.isEmpty) continue;
        final height = s['height']?.toString() ?? '';
        final quality = height.isNotEmpty ? '${height}p' : 'Auto';
        final video = MVideo();
        video.url = streamUrl;
        video.quality = quality;
        video.originalUrl = streamUrl;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // Sort highest quality first
    videos.sort((a, b) {
      final aH = int.tryParse(a.quality.replaceAll('p', '')) ?? 0;
      final bH = int.tryParse(b.quality.replaceAll('p', '')) ?? 0;
      return bH.compareTo(aH);
    });

    return videos;
  }

  @override
  List<dynamic> getFilterList() => [];
}

Hanime main(MSource source) => Hanime(source: source);
