// Coomer.su - Content aggregator (OnlyFans, Fansly)
// Same API as Kemono at /api/v1/

import 'package:mangayomi/bridge_lib.dart';

class Coomer extends MProvider {
  Coomer({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    final offset = (page - 1) * 50;
    final url = '$baseUrl/api/v1/posts?o=$offset';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parsePosts(res.body);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return getPopular(page);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final offset = (page - 1) * 50;
    final q = Uri.encodeComponent(query);
    final url = '$baseUrl/api/v1/posts?q=$q&o=$offset';
    final res = await client.get(url, headers: {'Referer': '$baseUrl/'});
    return _parsePosts(res.body);
  }

  @override
  Future<MManga> getDetail(String url) async {
    // url: /service/user/userid
    final res = await client.get('$baseUrl/api/v1$url', headers: {'Referer': '$baseUrl/'});
    final manga = MManga();

    // Profile info
    final nameMatch = RegExp(r'"name"\s*:\s*"([^"]*)"').firstMatch(res.body);
    if (nameMatch != null) manga.name = nameMatch.group(1);

    // Get posts for this creator
    final postsRes = await client.get('$baseUrl/api/v1$url/posts?o=0', headers: {'Referer': '$baseUrl/'});

    // Parse as chapters (each post = a chapter)
    final chapters = <MChapter>[];
    final postPattern = RegExp(
      r'"id"\s*:\s*"([^"]+)".*?"title"\s*:\s*"((?:[^"\\]|\\.)*)".*?"published"\s*:\s*"([^"]*)"',
      dotAll: true,
    );
    // Split by individual post objects
    final postObjects = RegExp(r'\{[^{}]*"id"[^{}]*"title"[^{}]*\}').allMatches(postsRes.body);
    for (final obj in postObjects) {
      final str = obj.group(0)!;
      final idMatch = RegExp(r'"id"\s*:\s*"([^"]+)"').firstMatch(str);
      final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(str);
      final dateMatch = RegExp(r'"published"\s*:\s*"([^"]*)"').firstMatch(str);

      if (idMatch != null && titleMatch != null) {
        final ch = MChapter();
        ch.name = titleMatch.group(1)!.replaceAll(r'\"', '"');
        ch.url = '$url/post/${idMatch.group(1)}';
        if (dateMatch != null) ch.dateUpload = dateMatch.group(1);
        chapters.add(ch);
      }
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // url: /service/user/userid/post/postid
    final res = await client.get('$baseUrl/api/v1$url', headers: {'Referer': '$baseUrl/'});
    final pages = <String>[];

    // Extract file
    final fileMatch = RegExp(r'"file"\s*:\s*\{[^}]*"path"\s*:\s*"([^"]+)"').firstMatch(res.body);
    if (fileMatch != null) {
      final path = fileMatch.group(1)!;
      pages.add(path.startsWith('http') ? path : '$baseUrl/data$path');
    }

    // Extract attachments
    final attachPattern = RegExp(r'"path"\s*:\s*"([^"]+)"');
    final attachSection = RegExp(r'"attachments"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(res.body);
    if (attachSection != null) {
      for (final m in attachPattern.allMatches(attachSection.group(1)!)) {
        final path = m.group(1)!;
        final fullUrl = path.startsWith('http') ? path : '$baseUrl/data$path';
        if (!pages.contains(fullUrl)) pages.add(fullUrl);
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parsePosts(String body) {
    final mangaList = <MManga>[];

    // Each post in the API response represents a creator's post
    // Group by user for the browse view
    final seen = <String>{};
    final userPattern = RegExp(
      r'"user"\s*:\s*"([^"]+)".*?"service"\s*:\s*"([^"]+)"',
      dotAll: true,
    );

    final postObjects = RegExp(r'\{[^{}]*"user"[^{}]*"service"[^{}]*\}').allMatches(body);
    for (final obj in postObjects) {
      final str = obj.group(0)!;
      final userMatch = RegExp(r'"user"\s*:\s*"([^"]+)"').firstMatch(str);
      final serviceMatch = RegExp(r'"service"\s*:\s*"([^"]+)"').firstMatch(str);
      final titleMatch = RegExp(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(str);

      if (userMatch != null && serviceMatch != null) {
        final userId = userMatch.group(1)!;
        final service = serviceMatch.group(1)!;
        final key = '$service/$userId';
        if (seen.contains(key)) continue;
        seen.add(key);

        final manga = MManga();
        manga.name = titleMatch?.group(1)?.replaceAll(r'\"', '"') ?? 'Unknown';
        manga.link = '/$service/user/$userId';
        manga.imageUrl = '$baseUrl/icons/$service/$userId';
        mangaList.add(manga);
      }
    }

    return MPages(mangaList, mangaList.length >= 25);
  }
}

Coomer main(MSource source) {
  return Coomer(source: source);
}
