// Luscious.net - Adult comics (GraphQL API)

import 'package:mangayomi/bridge_lib.dart';

class Luscious extends MProvider {
  Luscious({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;
  String get apiUrl => '$baseUrl/graphql/nobatch/';

  Future<String> _query(String query) async {
    final res = await client.post(apiUrl,
      headers: {
        'Referer': '$baseUrl/',
        'Content-Type': 'application/json',
      },
      body: query,
    );
    return res.body;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final body = '{"operationName":"AlbumList","query":"query AlbumList{album{list(input:{display:rating,page:$page,items_per_page:30}){info{page has_next_page}items{id title url_title cover{url}}}}}","variables":{}}';
    final res = await _query(body);
    return _parseAlbums(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final body = '{"operationName":"AlbumList","query":"query AlbumList{album{list(input:{display:date_newest,page:$page,items_per_page:30}){info{page has_next_page}items{id title url_title cover{url}}}}}","variables":{}}';
    final res = await _query(body);
    return _parseAlbums(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = query.replaceAll('"', '\\"');
    final body = '{"operationName":"AlbumList","query":"query AlbumList{album{list(input:{display:date_newest,page:$page,items_per_page:30,search_query:\\"$q\\"}){info{page has_next_page}items{id title url_title cover{url}}}}}","variables":{}}';
    final res = await _query(body);
    return _parseAlbums(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    // url is like /albums/title_123/
    final idMatch = RegExp(r'_(\d+)/?$').firstMatch(url);
    final albumId = idMatch?.group(1) ?? '';

    final body = '{"operationName":"AlbumGet","query":"query AlbumGet{album{get(id:\\"$albumId\\"){... on Album{id title description language{title}tags{text}content{total}created}}}}","variables":{}}';
    final res = await _query(body);
    final manga = MManga();

    final titleMatch = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(res);
    if (titleMatch != null) manga.name = titleMatch.group(1);

    final descMatch = RegExp(r'"description"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(res);
    if (descMatch != null) manga.description = descMatch.group(1)!.replaceAll(r'\n', '\n');

    manga.imageUrl = '';

    final tagMatches = RegExp(r'"text"\s*:\s*"([^"]*)"').allMatches(res);
    if (tagMatches.isNotEmpty) {
      manga.genre = tagMatches.map((m) => m.group(1)!).toList();
    }

    // Get pages as chapters (single chapter = all pages)
    final ch = MChapter();
    ch.name = 'Full Album';
    ch.url = url;
    manga.chapters = [ch];

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    final idMatch = RegExp(r'_(\d+)/?$').firstMatch(url);
    final albumId = idMatch?.group(1) ?? '';
    final pages = <String>[];

    var page = 1;
    var hasNext = true;
    while (hasNext && page <= 50) {
      final body = '{"operationName":"AlbumListOwnPictures","query":"query AlbumListOwnPictures{picture{list(input:{filters:[{name:\\"album_id\\",value:\\"$albumId\\"}],display:position,page:$page,items_per_page:50}){info{has_next_page}items{url_to_original}}}}","variables":{}}';
      final res = await _query(body);

      final urlMatches = RegExp(r'"url_to_original"\s*:\s*"([^"]*)"').allMatches(res);
      for (final m in urlMatches) {
        pages.add(m.group(1)!.replaceAll(r'\/', '/'));
      }

      hasNext = res.contains('"has_next_page":true');
      page++;
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseAlbums(String body) {
    final mangaList = <MManga>[];

    final pattern = RegExp(
      r'"id"\s*:\s*"?(\d+)"?.*?"title"\s*:\s*"([^"]*)".*?"url_title"\s*:\s*"([^"]*)"',
      dotAll: true,
    );

    final itemsMatch = RegExp(r'"items"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
    if (itemsMatch != null) {
      final items = itemsMatch.group(1)!;
      final objects = RegExp(r'\{[^{}]*"id"[^{}]*\}').allMatches(items);
      for (final obj in objects) {
        final str = obj.group(0)!;
        final idMatch = RegExp(r'"id"\s*:\s*"?(\d+)"?').firstMatch(str);
        final titleMatch = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(str);
        final urlMatch = RegExp(r'"url_title"\s*:\s*"([^"]*)"').firstMatch(str);
        final coverMatch = RegExp(r'"url"\s*:\s*"([^"]*)"').firstMatch(str);

        if (idMatch != null && titleMatch != null) {
          final manga = MManga();
          manga.name = titleMatch.group(1);
          final urlTitle = urlMatch?.group(1) ?? '';
          manga.link = '$baseUrl/albums/${urlTitle}_${idMatch.group(1)}/';
          if (coverMatch != null) {
            manga.imageUrl = coverMatch.group(1)!.replaceAll(r'\/', '/');
          }
          mangaList.add(manga);
        }
      }
    }

    final hasNext = body.contains('"has_next_page":true');
    return MPages(mangaList, hasNext);
  }
}

Luscious main(MSource source) {
  return Luscious(source: source);
}
