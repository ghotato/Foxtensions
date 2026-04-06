// Luscious.net - Adult comics (GraphQL API)
// GraphQL API source — uses GET with query params

import 'package:foxlations/bridge_lib.dart';

class Luscious extends MProvider {
  Luscious({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  Map<String, String> get _headers => {
    'Referer': '$baseUrl/',
  };

  // GraphQL queries sent as GET query parameters
  Future<String> _gql(String operationName, String query, String variables) async {
    final q = Uri.encodeComponent(query);
    final v = Uri.encodeComponent(variables);
    final url = '$baseUrl/graphql/nobatch/?operationName=$operationName&query=$q&variables=$v';
    final res = await client.get(url, headers: _headers);
    return res.body;
  }

  final String _albumListQuery = 'query AlbumList(\$input: AlbumListInput!) { album { list(input: \$input) { info { page has_next_page } items { url title cover { url } } } } }';

  final String _albumGetQuery = 'query AlbumGet(\$id: ID!) { album { get(id: \$id) { ... on Album { id title description created cover { url } language { title } tags { category text } genres { title } content { title } number_of_pictures } } } }';

  final String _pictureListQuery = 'query AlbumListOwnPictures(\$input: PictureListInput!) { picture { list(input: \$input) { info { has_next_page } items { url_to_original thumbnails { url } position } } } }';

  @override
  Future<MPages> getPopular(int page) async {
    final vars = '{"input":{"display":"rating_all_time","page":$page,"filters":[]}}';
    final res = await _gql('AlbumList', _albumListQuery, vars);
    return _parseAlbums(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final vars = '{"input":{"display":"date_newest","page":$page,"filters":[]}}';
    final res = await _gql('AlbumList', _albumListQuery, vars);
    return _parseAlbums(res);
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = query.replaceAll('"', '\\"');
    final vars = '{"input":{"display":"date_newest","page":$page,"filters":[{"name":"search_query","value":"$q"}]}}';
    final res = await _gql('AlbumList', _albumListQuery, vars);
    return _parseAlbums(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final albumId = _extractId(url);
    final vars = '{"id":"$albumId"}';
    final res = await _gql('AlbumGet', _albumGetQuery, vars);
    final data = jsonDecode(res);
    final manga = MManga();

    final album = data['data']['album']['get'];
    if (album != null) {
      manga.name = (album['title'] ?? '').toString();
      manga.description = (album['description'] ?? '').toString();

      final cover = album['cover'];
      if (cover != null) {
        var coverUrl = (cover['url'] ?? '').toString();
        if (coverUrl.startsWith('//')) {
          coverUrl = 'https:$coverUrl';
        }
        manga.imageUrl = coverUrl;
      }

      // Tags
      final tags = album['tags'];
      if (tags is List) {
        manga.genre = tags.map((t) => t['text'].toString()).toList();
      }
    }

    // Fetch all pictures — each picture becomes a chapter
    final chapters = <MChapter>[];
    var picPage = 1;
    var hasNext = true;
    var idx = 1;
    while (hasNext) {
      final picVars = '{"input":{"display":"position","page":$picPage,"filters":[{"name":"album_id","value":"$albumId"}]}}';
      final picRes = await _gql('AlbumListOwnPictures', _pictureListQuery, picVars);
      final picData = jsonDecode(picRes);

      final picList = picData['data']['picture']['list'];
      final items = picList['items'];
      if (items is List) {
        for (final pic in items) {
          var imgUrl = (pic['url_to_original'] ?? '').toString();
          if (imgUrl.isEmpty) {
            final thumbs = pic['thumbnails'];
            if (thumbs is List && thumbs.isNotEmpty) {
              imgUrl = (thumbs[0]['url'] ?? '').toString();
            }
          }
          if (imgUrl.startsWith('//')) {
            imgUrl = 'https:$imgUrl';
          }
          if (imgUrl.isNotEmpty) {
            final ch = MChapter();
            final title = (pic['title'] ?? '').toString();
            ch.name = title.isNotEmpty ? '$idx - $title' : 'Page $idx';
            // Store the direct image URL as the chapter URL
            ch.url = imgUrl;
            chapters.add(ch);
            idx++;
          }
        }
      }

      hasNext = picList['info']['has_next_page'] == true;
      picPage++;
    }
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    // Each chapter URL is a direct image URL
    return [url];
  }

  String _extractId(String url) {
    // URL: /albums/title_12345/ → extract 12345
    var clean = url;
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final idx = clean.lastIndexOf('_');
    if (idx >= 0) {
      return clean.substring(idx + 1);
    }
    return '';
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseAlbums(String body) {
    final mangaList = <MManga>[];
    final data = jsonDecode(body);

    final list = data['data']['album']['list'];
    final items = list['items'];
    if (items is List) {
      for (final item in items) {
        final manga = MManga();
        manga.name = (item['title'] ?? '').toString();
        final albumUrl = (item['url'] ?? '').toString();
        manga.link = albumUrl.startsWith('http') ? albumUrl : '$baseUrl$albumUrl';

        final cover = item['cover'];
        if (cover != null) {
          var coverUrl = (cover['url'] ?? '').toString();
          if (coverUrl.startsWith('//')) {
            coverUrl = 'https:$coverUrl';
          }
          manga.imageUrl = coverUrl;
        }

        if (manga.name!.isNotEmpty) {
          mangaList.add(manga);
        }
      }
    }

    final hasNext = list['info']['has_next_page'] == true;
    return MPages(mangaList, hasNext);
  }
}

Luscious main(MSource source) {
  return Luscious(source: source);
}
