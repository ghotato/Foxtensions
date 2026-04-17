import 'package:foxlations/bridge_lib.dart';

class Pinayjuicy extends MProvider {
  Pinayjuicy({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => 'https://pinayjuicy.com';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': '$baseUrl/',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      };

  @override
  Future<MPages> getPopular(int page) async {
    // /most-viewed/ returns 403; use homepage which lists recent content
    final url = page == 1 ? baseUrl : '$baseUrl/page/$page/';
    final res = await client.get(url, headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = page == 1 ? baseUrl : '$baseUrl/page/$page/';
    final res = await client.get(url, headers: _headers);
    return _parseList(res.body);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final url = page == 1
        ? '$baseUrl/?s=$q'
        : '$baseUrl/page/$page/?s=$q';
    final res = await client.get(url, headers: _headers);
    return _parseList(res.body);
  }

  MPages _parseList(String html) {
    final doc = parseHtml(html);
    final list = <MManga>[];

    // Try common WordPress video theme selectors
    final items = doc.querySelectorAll(
        'article.post, article.video, .video-item, .post-item, .thumb-item, article');

    for (final item in items) {
      // Skip non-content articles (sidebar, etc.)
      final link = item.querySelector('a[href*="${baseUrl}"], a[href^="/"]');
      final anyLink = item.querySelector('a');
      final a = link ?? anyLink;
      if (a == null) continue;

      final href = a.attr('href') ?? '';
      if (href.isEmpty || href == '#' || href == baseUrl || href == '$baseUrl/') continue;

      final fullHref = href.startsWith('http') ? href : '$baseUrl$href';
      // Skip pagination/category links
      if (fullHref.contains('/page/') || fullHref.contains('/category/') ||
          fullHref.contains('/tag/') || fullHref == baseUrl) continue;

      // Title from various selectors
      final titleEl = item.querySelector(
          '.entry-title, h2.title, h3.title, .video-title, h2 a, h3 a, h2, h3');
      final name = titleEl?.text.trim() ??
          a.attr('title') ??
          a.text.trim();
      if (name.isEmpty) continue;

      // Thumbnail — try data-src (lazy load) first, then src
      final img = item.querySelector('img');
      final imageUrl = img?.attr('data-src') ??
          img?.attr('data-lazy-src') ??
          img?.attr('src') ?? '';

      final m = MManga();
      m.name = name;
      m.link = fullHref;
      m.imageUrl = imageUrl;
      list.add(m);
    }

    final hasNext = doc.querySelector('a.next, .next.page-numbers, [rel="next"], .nav-next a') != null;
    return MPages(list, hasNext);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await client.get(url, headers: _headers);
    final doc = parseHtml(res.body);

    final manga = MManga();
    manga.name = doc.querySelector('h1.entry-title, h1.post-title, h1.title, h1')?.text.trim() ??
        doc.querySelector('meta[property="og:title"]')?.attr('content') ?? 'Unknown';

    manga.imageUrl = doc.querySelector('meta[property="og:image"]')?.attr('content') ??
        doc.querySelector('.post-thumbnail img, .featured-image img, .entry-content img')
            ?.attr('src') ?? '';

    manga.description = doc.querySelector('.entry-content p, .post-content p, .description')
        ?.text.trim() ?? '';

    // Tags / categories
    final tags = doc.querySelectorAll('.post-tags a, .tags a, .entry-tags a, .tag a, .cat-links a');
    if (tags.isNotEmpty) {
      manga.genre = tags.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();
    }

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

    // 1. JW Player — sources array: [{file:"..."}] or setup({file:"..."})
    final jwSources = RegExp(r'''sources\s*:\s*\[\s*\{[^}]*file\s*:\s*["']([^"']+)["']''')
        .firstMatch(html);
    if (jwSources != null) {
      final u = jwSources.group(1) ?? '';
      if (u.isNotEmpty) {
        final video = MVideo();
        video.url = u;
        video.quality = u.contains('.m3u8') ? 'HLS' : 'MP4';
        video.originalUrl = url;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // 2. JW Player single file setup({file:"..."})
    if (videos.isEmpty) {
      final jwFile = RegExp(r'''[Ss]etup\s*\(\s*\{[^}]*file\s*:\s*["']([^"']+)["']''')
          .firstMatch(html);
      if (jwFile != null) {
        final u = jwFile.group(1) ?? '';
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = u.contains('.m3u8') ? 'HLS' : 'MP4';
          video.originalUrl = url;
          video.headers = _headers;
          videos.add(video);
        }
      }
    }

    // 3. VideoJS data-setup src
    if (videos.isEmpty) {
      final vjsMatch = RegExp(r'''data-setup\s*=\s*["']([^"']+)["']''').firstMatch(html);
      if (vjsMatch != null) {
        final setup = vjsMatch.group(1) ?? '';
        final srcMatch = RegExp(r'"src"\s*:\s*"([^"]+)"').firstMatch(setup);
        if (srcMatch != null) {
          final u = srcMatch.group(1) ?? '';
          if (u.isNotEmpty) {
            final video = MVideo();
            video.url = u;
            video.quality = u.contains('.m3u8') ? 'HLS' : 'MP4';
            video.originalUrl = url;
            video.headers = _headers;
            videos.add(video);
          }
        }
      }
    }

    // 4. HTML5 <source src="..."> tags
    if (videos.isEmpty) {
      final doc = parseHtml(html);
      final sources = doc.querySelectorAll('source[src], video[src]');
      for (final src in sources) {
        final u = src.attr('src') ?? '';
        if (u.isEmpty) continue;
        final fullUrl = u.startsWith('http') ? u : '$baseUrl$u';
        final video = MVideo();
        video.url = fullUrl;
        video.quality = src.attr('label') ?? src.attr('res') ?? (fullUrl.contains('.m3u8') ? 'HLS' : 'MP4');
        video.originalUrl = url;
        video.headers = _headers;
        videos.add(video);
      }
    }

    // 5. Scan for embedded iframe and follow it
    if (videos.isEmpty) {
      final doc = parseHtml(html);
      final iframe = doc.querySelector('iframe[src*="embed"], iframe[src*="player"], iframe[src]');
      if (iframe != null) {
        final embedUrl = iframe.attr('src') ?? '';
        if (embedUrl.isNotEmpty) {
          final embedHeaders = {
            ...(_headers),
            'Referer': url,
          };
          try {
            final embedRes = await client.get(
                embedUrl.startsWith('http') ? embedUrl : '$baseUrl$embedUrl',
                headers: embedHeaders);
            final embedHtml = embedRes.body;

            // HLS in embed
            var remaining = embedHtml;
            final hlsPat = RegExp(r'https?://\S+\.m3u8');
            var m = hlsPat.firstMatch(remaining);
            while (m != null) {
              final u = m.group(0)!.split('"').first.split("'").first;
              if (u.isNotEmpty) {
                final video = MVideo();
                video.url = u;
                video.quality = 'HLS';
                video.originalUrl = embedUrl;
                video.headers = embedHeaders;
                videos.add(video);
              }
              remaining = remaining.substring(m.end);
              m = hlsPat.firstMatch(remaining);
            }

            // MP4 in embed
            if (videos.isEmpty) {
              remaining = embedHtml;
              final mp4Pat = RegExp(r'https?://\S+\.mp4');
              m = mp4Pat.firstMatch(remaining);
              while (m != null) {
                final u = m.group(0)!.split('"').first.split("'").first;
                if (u.isNotEmpty) {
                  final video = MVideo();
                  video.url = u;
                  video.quality = 'MP4';
                  video.originalUrl = embedUrl;
                  video.headers = embedHeaders;
                  videos.add(video);
                }
                remaining = remaining.substring(m.end);
                m = mp4Pat.firstMatch(remaining);
              }
            }
          } catch (_) {}
        }
      }
    }

    // 6. Final fallback: scan raw HTML for any m3u8/mp4 URLs
    if (videos.isEmpty) {
      var remaining = html;
      final hlsPat = RegExp(r'https?://\S+\.m3u8');
      var m = hlsPat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'HLS';
          video.originalUrl = url;
          video.headers = _headers;
          videos.add(video);
        }
        remaining = remaining.substring(m.end);
        m = hlsPat.firstMatch(remaining);
      }
    }

    if (videos.isEmpty) {
      var remaining = html;
      final mp4Pat = RegExp(r'https?://\S+\.mp4');
      var m = mp4Pat.firstMatch(remaining);
      while (m != null) {
        final u = m.group(0)!.split('"').first.split("'").first;
        if (u.isNotEmpty) {
          final video = MVideo();
          video.url = u;
          video.quality = 'MP4';
          video.originalUrl = url;
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

Pinayjuicy main(MSource source) => Pinayjuicy(source: source);
