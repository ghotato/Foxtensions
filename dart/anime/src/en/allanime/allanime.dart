// AllAnime (allmanga.to) - GraphQL API-based anime source

import 'package:foxlations/bridge_lib.dart';

class AllAnime extends MProvider {
  AllAnime({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://allmanga.to';
  String get apiUrl => 'https://api.allanime.day/api';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
        'Origin': baseUrl,
      };

  Future<Map<String, dynamic>> _gql(String query, [Map<String, dynamic>? variables]) async {
    final body = jsonEncode({'query': query, if (variables != null) 'variables': variables});
    final res = await client.post(apiUrl,
        headers: {..._headers, 'Content-Type': 'application/json'}, body: body);
    final data = jsonDecode(res.body);
    return (data['data'] as Map<String, dynamic>?) ?? {};
  }

  static const _showFields = '''
    _id name thumbnail type season { year quarter }
    availableEpisodes { sub dub }
  ''';

  @override
  Future<MPages> getPopular(int page) async {
    final data = await _gql('''
      { shows(search: {sortBy: "Top", allowAdult: true}, limit: 26, page: $page, countryOrigin: "JP") {
          edges { $_showFields }
      } }
    ''');
    return _parseShows(data, 'shows');
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final data = await _gql('''
      { shows(search: {sortBy: "Recent", allowAdult: true}, limit: 26, page: $page) {
          edges { $_showFields }
      } }
    ''');
    return _parseShows(data, 'shows');
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final escaped = query.replaceAll('"', '\\"');
    final data = await _gql('''
      { shows(search: {query: "$escaped", sortBy: "Top", allowAdult: true}, limit: 26, page: $page) {
          edges { $_showFields }
      } }
    ''');
    return _parseShows(data, 'shows');
  }

  MPages _parseShows(Map<String, dynamic> data, String key) {
    final edges = (data[key]?['edges'] as List? ?? []);
    final list = edges.map((e) {
      final m = MManga();
      m.name = e['name']?.toString() ?? 'Unknown';
      m.imageUrl = e['thumbnail']?.toString() ?? '';
      m.link = '$baseUrl/anime/${e['_id']}';
      return m;
    }).toList();
    return MPages(list, list.length >= 26);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final id = url.split('/').last;
    final data = await _gql('''
      { show(_id: "$id") {
          _id name description thumbnail type status
          genres studios availableEpisodes { sub dub }
          season { year quarter }
      } }
    ''');
    final show = data['show'] as Map? ?? {};

    final manga = MManga();
    manga.name = show['name']?.toString() ?? 'Unknown';
    manga.imageUrl = show['thumbnail']?.toString() ?? '';
    manga.description = show['description']?.toString() ?? '';
    manga.genre = (show['genres'] as List? ?? []).map((g) => g.toString()).toList();

    final status = show['status']?.toString().toLowerCase() ?? '';
    if (status.contains('finished') || status.contains('completed')) {
      manga.status = MangaStatus.completed;
    } else if (status.contains('ongoing') || status.contains('releasing')) {
      manga.status = MangaStatus.ongoing;
    }

    // Build episode list from available count
    final availSub = (show['availableEpisodes']?['sub'] as num? ?? 0).toInt();
    final availDub = (show['availableEpisodes']?['dub'] as num? ?? 0).toInt();
    final total = availSub > 0 ? availSub : availDub;
    final lang = availSub > 0 ? 'sub' : 'dub';

    final chapters = <MChapter>[];
    for (var i = 1; i <= total; i++) {
      final chapter = MChapter();
      chapter.name = 'Episode $i';
      chapter.url = '$url/episode/$i/$lang';
      chapters.add(chapter);
    }
    manga.chapters = chapters.reversed.toList();

    return manga;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    // URL format: .../anime/{id}/episode/{num}/{lang}
    final parts = url.split('/');
    final lang = parts.last;
    final epNum = parts[parts.length - 2];
    final animeId = parts[parts.length - 4];

    final data = await _gql('''
      { episode(showId: "$animeId", episodeString: "$epNum", translationType: "$lang") {
          sourceUrls
      } }
    ''');

    final episode = data['episode'] as Map? ?? {};
    final sourceUrls = (episode['sourceUrls'] as List? ?? []);
    final List<MVideo> videos = [];

    for (final src in sourceUrls) {
      final rawUrl = src['sourceUrl']?.toString() ?? '';
      final sourceName = src['sourceName']?.toString() ?? '';
      if (rawUrl.isEmpty) continue;

      // AllAnime encodes URLs — try direct first
      var streamUrl = rawUrl;
      if (rawUrl.startsWith('--')) {
        // Decode the mangled URL: replace '--' prefix, then base64-like decode
        streamUrl = _decodeAllAnimeUrl(rawUrl);
      }

      if (streamUrl.contains('.m3u8') || streamUrl.startsWith('http')) {
        final video = MVideo();
        video.url = streamUrl;
        video.quality = sourceName.isNotEmpty ? sourceName : 'Source';
        video.originalUrl = rawUrl;
        video.headers = _headers;
        videos.add(video);
      }
    }

    return videos;
  }

  String _decodeAllAnimeUrl(String encoded) {
    // AllAnime replaces each char pair XX with char(int('XX', 16))
    // The encoded string starts with '--' followed by hex pairs
    try {
      final hex = encoded.replaceFirst('--', '');
      final buf = StringBuffer();
      for (var i = 0; i < hex.length - 1; i += 2) {
        final byte = int.parse(hex.substring(i, i + 2), radix: 16);
        buf.writeCharCode(byte);
      }
      return buf.toString();
    } catch (_) {
      return encoded;
    }
  }

  @override
  List<dynamic> getFilterList() => [];
}

AllAnime main(MSource source) => AllAnime(source: source);
