// AnimePahe - anime streaming via animepahe.pw API + Kwik CDN
// API: https://animepahe.pw/api?m=...

import 'package:foxlations/bridge_lib.dart';

class AnimePahe extends MProvider {
  AnimePahe({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://animepahe.pw';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$baseUrl/',
      };

  // ── Browse ──────────────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final res = await client.get(
        '$baseUrl/api?m=airing&sort=episode_count&order=desc&page=$page',
        headers: _headers);
    return _parseAnimeList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await client.get(
        '$baseUrl/api?m=airing&sort=last_update&order=desc&page=$page',
        headers: _headers);
    return _parseAnimeList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final res = await client.get('$baseUrl/api?m=search&q=$q', headers: _headers);
    final data = jsonDecode(res.body);
    final hits = (data['data'] as List? ?? []);
    final list = hits.map((h) {
      final m = MManga();
      m.name = h['title']?.toString() ?? 'Unknown';
      m.imageUrl = h['image']?.toString() ?? '';
      m.link = '$baseUrl/anime/${h['slug']}';
      return m;
    }).toList();
    return MPages(list, false);
  }

  MPages _parseAnimeList(String body) {
    final data = jsonDecode(body);
    final entries = (data['data'] as List? ?? []);
    final list = entries.map((e) {
      final m = MManga();
      m.name = e['anime_title']?.toString() ?? e['title']?.toString() ?? 'Unknown';
      m.imageUrl = e['snapshot']?.toString() ?? e['image']?.toString() ?? '';
      m.link = '$baseUrl/anime/${e['anime_slug'] ?? e['slug'] ?? ''}';
      return m;
    }).toList();
    final lastPage = data['last_page'] as int? ?? 1;
    final curPage = data['current_page'] as int? ?? 1;
    return MPages(list, curPage < lastPage);
  }

  // ── Detail ───────────────────────────────────────────────────────────────

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final doc = parseHtml(html);

    final manga = MManga();
    manga.name = doc.querySelector('h1, .title-wrapper h1')?.text.trim() ?? 'Unknown';
    manga.imageUrl = doc.querySelector('.anime-cover img, .poster img')?.attr('src') ?? '';
    manga.description = doc.querySelector('.anime-synopsis p, .synopsis')?.text.trim() ?? '';

    final tags = doc.querySelectorAll('.anime-genre a, .genre-list a');
    manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();

    // Extract anime session UUID from page JS
    final sessionMatch = RegExp('let session = "([a-f0-9-]+)"').firstMatch(html)
        ?? RegExp("session\\s*=\\s*\"([a-f0-9-]+)\"").firstMatch(html);
    final session = sessionMatch?.group(1) ?? '';

    if (session.isNotEmpty) {
      manga.chapters = await _fetchEpisodes(session, url);
    }

    return manga;
  }

  Future<List<MChapter>> _fetchEpisodes(String session, String animeUrl) async {
    final chapters = <MChapter>[];
    int page = 1;
    int lastPage = 1;

    do {
      final res = await client.get(
          '$baseUrl/api?m=release&id=$session&sort=episode_asc&page=$page',
          headers: _headers);
      final data = jsonDecode(res.body);
      lastPage = (data['last_page'] as num? ?? 1).toInt();
      final episodes = (data['data'] as List? ?? []);

      for (final ep in episodes) {
        final chapter = MChapter();
        final epNum = ep['episode']?.toString() ?? '';
        final title = ep['title']?.toString() ?? '';
        chapter.name = title.isNotEmpty ? 'Ep $epNum - $title' : 'Episode $epNum';
        chapter.url = '$baseUrl/play/$session/${ep['session']}';
        chapter.dateUpload = ep['created_at']?.toString() ?? '';
        chapters.add(chapter);
      }
      page++;
    } while (page <= lastPage);

    return chapters;
  }

  // ── Video extraction ─────────────────────────────────────────────────────

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await client.get(url, headers: _headers);
    final html = res.body;
    final doc = parseHtml(html);

    final List<MVideo> videos = [];

    // Collect Kwik embed links from the player page
    // AnimeP ahe puts sources in buttons with data-src or href pointing to kwik
    final sources = <Map<String, String>>[];

    // Method 1: look for kwik buttons/links
    final kwikLinks = doc.querySelectorAll('[data-src*="kwik"], a[href*="kwik.si"]');
    for (final el in kwikLinks) {
      final kwikUrl = el.attr('data-src') ?? el.attr('href') ?? '';
      if (kwikUrl.isEmpty) continue;
      final fansub = el.attr('data-fansub') ?? el.attr('data-disc') ?? '';
      final audio = el.attr('data-audio') ?? '';
      sources.add({'url': kwikUrl, 'fansub': fansub, 'audio': audio});
    }

    // Method 2: scan page source for kwik URLs
    if (sources.isEmpty) {
      var remaining = html;
      final kwikPat = RegExp('https://kwik\\.si/e/[A-Za-z0-9]+');
      var m = kwikPat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!;
        sources.add({'url': u, 'fansub': '', 'audio': ''});
        remaining = remaining.substring(m.end);
        m = kwikPat.firstMatch(remaining);
      }
    }

    // Extract video from each Kwik embed
    for (final s in sources) {
      try {
        final streamUrl = await _extractKwik(s['url']!, url);
        if (streamUrl.isEmpty) continue;
        final label = [
          if ((s['fansub'] ?? '').isNotEmpty) s['fansub']!,
          if ((s['audio'] ?? '').isNotEmpty) s['audio']!,
        ].join(' - ');
        final video = MVideo();
        video.url = streamUrl;
        video.quality = label.isEmpty ? 'HLS' : label;
        video.originalUrl = s['url']!;
        video.headers = {
          'Referer': '$baseUrl/',
          'User-Agent': _headers['User-Agent']!,
        };
        videos.add(video);
      } catch (_) {}
    }

    return videos;
  }

  Future<String> _extractKwik(String kwikUrl, String referer) async {
    final res = await client.get(kwikUrl, headers: {
      'Referer': referer,
      'User-Agent': _headers['User-Agent']!,
    });
    final html = res.body;

    // Find the eval(function(p,a,c,k,e,d){...}) packer block
    final evalMatch = RegExp('eval\\(function\\(p,a,c,k,e,d\\)').firstMatch(html);
    if (evalMatch == null) return '';

    final packedSection = html.substring(evalMatch.start);
    // The close of the eval call — grab enough text
    final endIdx = (packedSection.length).clamp(0, 6000);
    final packed = packedSection.substring(0, endIdx);

    final unpacked = _unpackPacker(packed);

    // Extract m3u8 URL from unpacked code
    final m3u8Match = RegExp("source='(https://[^']+\\.m3u8[^']*)'").firstMatch(unpacked)
        ?? RegExp('source="(https://[^"]+\\.m3u8[^"]*)"').firstMatch(unpacked)
        ?? RegExp("'(https://[^']+\\.m3u8[^']*)'").firstMatch(unpacked);

    return m3u8Match?.group(1) ?? '';
  }

  /// P.A.C.K.E.R deobfuscator — decodes eval(function(p,a,c,k,e,d){...}(...))
  String _unpackPacker(String packed) {
    // Extract: }'encodedStr',base,count,'k0|k1|k2'
    final argsMatch = RegExp("\\}\\('([^']+)',(\\d+),(\\d+),'([^']+)'").firstMatch(packed);
    if (argsMatch == null) return packed;

    final p = argsMatch.group(1)!;
    final a = int.parse(argsMatch.group(2)!);
    final k = argsMatch.group(4)!.split('|');

    // Decode a single token from base-a back to its key index
    String decodeToken(String word) {
      var n = 0;
      for (var i = 0; i < word.length; i++) {
        final ch = word[i];
        int digit;
        if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
          digit = ch.codeUnitAt(0) - '0'.codeUnitAt(0);
        } else if (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) {
          digit = ch.codeUnitAt(0) - 'a'.codeUnitAt(0) + 10;
        } else if (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) {
          digit = ch.codeUnitAt(0) - 'A'.codeUnitAt(0) + 36;
        } else {
          digit = 0;
        }
        n = n * a + digit;
      }
      return (n < k.length && k[n].isNotEmpty) ? k[n] : word;
    }

    // Replace each \b\w+\b token with its decoded value
    var result = '';
    var remaining = p;
    final wordPat = RegExp('\\b\\w+\\b');
    var wm = wordPat.firstMatch(remaining);
    while (wm != null) {
      result += remaining.substring(0, wm.start) + decodeToken(wm.group(0)!);
      remaining = remaining.substring(wm.end);
      wm = wordPat.firstMatch(remaining);
    }
    return result + remaining;
  }

  @override
  List<dynamic> getFilterList() => [];
}

AnimePahe main(MSource source) => AnimePahe(source: source);
