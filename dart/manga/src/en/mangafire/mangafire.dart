// MangaFire - Custom source with VRF crypto
// VRF crypto for chapter/page fetching

import 'package:foxlations/bridge_lib.dart';

class MangaFire extends MProvider {
  MangaFire({required this.source});

  MSource source;
  final Client client = Client();

  String get baseUrl => source.baseUrl;

  Map<String, String> _getHeaders() {
    return {'Referer': '$baseUrl/'};
  }

  // ── VRF Crypto ─────────────────────────────────────────────

  final _rc4Keys = [
    'FgxyJUQDPUGSzwbAq/ToWn4/e8jYzvabE+dLMb1XU1o=',
    'CQx3CLwswJAnM1VxOqX+y+f3eUns03ulxv8Z+0gUyik=',
    'fAS+otFLkKsKAJzu3yU+rGOlbbFVq+u+LaS6+s1eCJs=',
    'Oy45fQVK9kq9019+VysXVlz1F9S1YwYKgXyzGlZrijo=',
    'aoDIdXezm2l3HrcnQdkPJTDT8+W6mcl2/02ewBHfPzg=',
  ];

  final _seeds32 = [
    'yH6MXnMEcDVWO/9a6P9W92BAh1eRLVFxFlWTHUqQ474=',
    'RK7y4dZ0azs9Uqz+bbFB46Bx2K9EHg74ndxknY9uknA=',
    'rqr9HeTQOg8TlFiIGZpJaxcvAaKHwMwrkqojJCpcvoc=',
    '/4GPpmZXYpn5RpkP7FC/dt8SXz7W30nUZTe8wb+3xmU=',
    'wsSGSBXKWA9q1oDJpjtJddVxH+evCfL5SO9HZnUDFU8=',
  ];

  final _prefixKeys = [
    'l9PavRg=',
    'Ml2v7ag1Jg==',
    'i/Va0UxrbMo=',
    'WFjKAHGEkQM=',
    '5Rr27rWd',
  ];

  // Base64 decode to byte list
  List<int> _b64Decode(String b64) {
    // Standard base64 decode
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final bytes = <int>[];
    var buf = 0;
    var bits = 0;
    for (var i = 0; i < b64.length; i++) {
      final c = b64[i];
      if (c == '=') break;
      final val = chars.indexOf(c);
      if (val < 0) continue;
      buf = (buf << 6) | val;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buf >> bits) & 0xff);
      }
    }
    return bytes;
  }

  // Base64 encode bytes to string (URL-safe)
  String _b64UrlEncode(List<int> bytes) {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      buf.write(chars[(b0 >> 2) & 0x3f]);
      buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3f]);
      if (i + 1 < bytes.length) {
        buf.write(chars[((b1 << 2) | (b2 >> 6)) & 0x3f]);
      }
      if (i + 2 < bytes.length) {
        buf.write(chars[b2 & 0x3f]);
      }
      i += 3;
    }
    // URL-safe: replace + with -, / with _, strip =
    return buf.toString().replaceAll('+', '-').replaceAll('/', '_');
  }

  // RC4 encrypt/decrypt
  List<int> _rc4(List<int> key, List<int> data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xff;
      final tmp = s[i]; s[i] = s[j]; s[j] = tmp;
    }
    final out = <int>[];
    var i = 0;
    j = 0;
    for (var k = 0; k < data.length; k++) {
      i = (i + 1) & 0xff;
      j = (j + s[i]) & 0xff;
      final tmp = s[i]; s[i] = s[j]; s[j] = tmp;
      out.add(data[k] ^ s[(s[i] + s[j]) & 0xff]);
    }
    return out;
  }

  // 8-bit operations
  int _add8(int c, int n) => (c + n) & 0xff;
  int _sub8(int c, int n) => (c - n + 256) & 0xff;
  int _xor8(int c, int n) => (c ^ n) & 0xff;
  int _rotl8(int c, int n) => ((c << n) | (c >> (8 - n))) & 0xff;
  int _rotr8(int c, int n) => ((c >> n) | (c << (8 - n))) & 0xff;

  // Apply one operation from schedule
  int _applyOp(String op, int c) {
    final parts = op.split(':');
    final name = parts[0];
    final n = int.parse(parts[1]);
    if (name == 'add') return _add8(c, n);
    if (name == 'sub') return _sub8(c, n);
    if (name == 'xor') return _xor8(c, n);
    if (name == 'rotl') return _rotl8(c, n);
    if (name == 'rotr') return _rotr8(c, n);
    return c;
  }

  // Transform: XOR with seed, then apply schedule op, interleave prefix bytes
  List<int> _transform(List<int> input, List<int> seed, List<int> prefix, List<String> schedule) {
    final out = <int>[];
    for (var i = 0; i < input.length; i++) {
      if (i < prefix.length) out.add(prefix[i]);
      final xored = (input[i] ^ seed[i % 32]) & 0xff;
      out.add(_applyOp(schedule[i % 10], xored));
    }
    return out;
  }

  // Schedules for each of the 5 stages
  final _schedules = [
    ['sub:223','rotr:4','rotr:4','add:234','rotr:7','rotr:2','rotr:7','sub:223','rotr:7','rotr:6'],
    ['add:19','rotr:7','add:19','rotr:6','add:19','rotr:1','add:19','rotr:6','rotr:7','rotr:4'],
    ['sub:223','rotr:1','add:19','sub:223','rotl:2','sub:223','add:19','rotl:1','rotl:2','rotl:1'],
    ['add:19','rotl:1','rotl:1','rotr:1','add:234','rotl:1','sub:223','rotl:6','rotl:4','rotl:1'],
    ['rotr:1','rotl:1','rotl:6','rotr:1','rotl:2','rotr:4','rotl:1','rotl:1','sub:223','rotl:2'],
  ];

  String _generateVrf(String input) {
    // URI-encode then convert to bytes
    var bytes = <int>[];
    final encoded = Uri.encodeComponent(input);
    for (var i = 0; i < encoded.length; i++) {
      bytes.add(encoded.codeUnitAt(i));
    }

    // 5 rounds of RC4 + transform
    for (var n = 0; n < 5; n++) {
      final rc4Key = _b64Decode(_rc4Keys[n]);
      final seed = _b64Decode(_seeds32[n]);
      final prefix = _b64Decode(_prefixKeys[n]);

      bytes = _rc4(rc4Key, bytes);
      bytes = _transform(bytes, seed, prefix, _schedules[n]);
    }

    return _b64UrlEncode(bytes);
  }

  // ── Source methods ─────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=most_viewed&language%5B%5D=en&page=$page';
    final res = await client.get(url, headers: _getHeaders());
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final url = '$baseUrl/filter?keyword=&sort=recently_updated&language%5B%5D=en&page=$page';
    final res = await client.get(url, headers: _getHeaders());
    return _parseList(Document(res.body));
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final q = Uri.encodeComponent(query);
    final vrf = _generateVrf(query);
    final url = '$baseUrl/filter?keyword=$q&language%5B%5D=en&page=$page&vrf=$vrf';
    final res = await client.get(url, headers: _getHeaders());
    return _parseList(Document(res.body));
  }

  @override
  Future<MManga> getDetail(String url) async {
    final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
    final res = await client.get(fullUrl, headers: _getHeaders());
    final doc = Document(res.body);
    final manga = MManga();

    final titleEl = doc.selectFirst('h1');
    if (titleEl != null) {
      manga.name = titleEl.text.trim();
    }

    final imgEl = doc.selectFirst('.poster img');
    if (imgEl != null) {
      manga.imageUrl = imgEl.getSrc();
    }

    final descEl = doc.selectFirst('#synopsis .modal-content');
    if (descEl != null) {
      manga.description = descEl.text.trim();
    }

    final statusEl = doc.selectFirst('.info > p');
    if (statusEl != null) {
      manga.status = parseStatus(statusEl.text);
    }

    // Extract manga ID from URL (after last dot: /manga/one-piece.rj2y -> rj2y)
    final mangaId = fullUrl.split('.').last.split('/').first;

    // Fetch chapter IDs via /ajax/read/{id}/chapter/{lang} (has data-id attributes)
    final chapters = <MChapter>[];
    try {
      final vrfKey = '$mangaId@chapter@en';
      final vrf = _generateVrf(vrfKey);

      // This endpoint returns <a data-id="12345">Chapter Name</a>
      final idUrl = '$baseUrl/ajax/read/$mangaId/chapter/en?vrf=$vrf';
      final idRes = await client.get(idUrl, headers: {
        'Referer': fullUrl,
        'X-Requested-With': 'XMLHttpRequest',
      });
      final idJson = jsonDecode(idRes.body);
      final idHtml = (idJson['result'] is Map) ? idJson['result']['html'] : idJson['result'];
      final idDoc = Document(idHtml ?? '');
      final idEls = idDoc.select('a');

      // Also fetch dates from /ajax/manga/{id}/chapter/{lang}
      Map<int, String> dateMap = {};
      try {
        final dateUrl = '$baseUrl/ajax/manga/$mangaId/chapter/en?vrf=$vrf';
        final dateRes = await client.get(dateUrl, headers: {
          'Referer': fullUrl,
          'X-Requested-With': 'XMLHttpRequest',
        });
        final dateJson = jsonDecode(dateRes.body);
        final dateHtml = dateJson['result'] ?? '';
        final dateDoc = Document(dateHtml);
        final dateEls = dateDoc.select('li');
        for (var i = 0; i < dateEls.length; i++) {
          final spans = dateEls[i].select('span');
          if (spans.length > 1) {
            dateMap[i] = spans[1].text.trim();
          }
        }
      } catch (_) {}

      for (var i = 0; i < idEls.length; i++) {
        final a = idEls[i];
        final dataId = a.attr('data-id');
        if (dataId == null || dataId.isEmpty) continue;

        final ch = MChapter();
        ch.url = dataId; // numeric ID for getPageList
        ch.name = a.text.trim();
        if (ch.name == null || ch.name!.isEmpty) {
          ch.name = 'Chapter ${i + 1}';
        }
        if (dateMap.containsKey(i)) {
          ch.dateUpload = dateMap[i];
        }
        chapters.add(ch);
      }
    } catch (e) {
      // Chapter fetch failed
    }

    manga.chapters = chapters;
    return manga;
  }

  @override
  Future<List<dynamic>> getPageList(String url) async {
    var chapId = url;

    // If url is not a numeric ID, load the page to extract the real chapter ID
    if (RegExp(r'^\d+$').firstMatch(chapId) == null) {
      final fullUrl = url.startsWith('http') ? url : '$baseUrl$url';
      final pageRes = await client.get(fullUrl, headers: _getHeaders());
      // Look for data-id on the reading container
      final idMatch = RegExp('data-id="(\\d+)"').firstMatch(pageRes.body);
      if (idMatch != null) {
        chapId = idMatch.group(1)!;
      } else {
        // Try finding the chapter ID in JS variables
        final jsMatch = RegExp('chapter_id["\']?\\s*[:=]\\s*["\']?(\\d+)').firstMatch(pageRes.body);
        if (jsMatch != null) {
          chapId = jsMatch.group(1)!;
        }
      }
    }

    final pages = <String>[];

    // Only proceed if we have a numeric ID
    if (RegExp(r'^\d+$').firstMatch(chapId) != null) {
      final vrf = _generateVrf('chapter@$chapId');
      final ajaxUrl = '$baseUrl/ajax/read/chapter/$chapId?vrf=$vrf';

      final res = await client.get(ajaxUrl, headers: {
        'Referer': '$baseUrl/',
        'X-Requested-With': 'XMLHttpRequest',
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final result = data['result'];
        if (result != null) {
          final images = result['images'];
          if (images is List) {
            for (final img in images) {
              if (img is List && img.isNotEmpty) {
                pages.add(img[0].toString());
              }
            }
          }
        }
      }
    }

    return pages;
  }

  @override
  List<dynamic> getFilterList() => [];

  @override
  List<dynamic> getSourcePreferences() => [];

  MPages _parseList(Document doc) {
    final mangaList = <MManga>[];

    var elements = doc.select('.original .unit .inner');
    if (elements.isEmpty) elements = doc.select('.unit .inner');
    if (elements.isEmpty) elements = doc.select('.original .unit');

    for (final el in elements) {
      final manga = MManga();

      final infoLink = el.selectFirst('.info a');
      if (infoLink != null) {
        var href = infoLink.attr('href') ?? '';
        if (href.isNotEmpty && !href.startsWith('http')) href = '$baseUrl$href';
        manga.link = href;
        manga.name = infoLink.text.trim();
      }

      if (manga.link == null || manga.link!.isEmpty) {
        final a = el.selectFirst('a');
        if (a != null) {
          var href = a.attr('href') ?? '';
          if (href.isNotEmpty && !href.startsWith('http')) href = '$baseUrl$href';
          manga.link = href;
          if (manga.name == null || manga.name!.isEmpty) manga.name = a.attr('title') ?? a.text.trim();
        }
      }

      final imgEl = el.selectFirst('img');
      if (imgEl != null) manga.imageUrl = imgEl.getSrc();

      if (manga.name != null && manga.name!.isNotEmpty && manga.link != null) {
        mangaList.add(manga);
      }
    }

    final nextPage = doc.selectFirst('.page-item.active + .page-item .page-link');
    return MPages(mangaList, nextPage != null);
  }
}

MangaFire main(MSource source) {
  return MangaFire(source: source);
}
