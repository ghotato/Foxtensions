// URL Auto-Generator - Detect manga site framework from URL and create source entry
// Run: dart run url_generator.dart <url>

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run url_generator.dart <manga_site_url>');
    print('Example: dart run url_generator.dart https://example.com');
    exit(1);
  }

  final url = args[0].replaceAll(RegExp(r'/+$'), ''); // trim trailing slashes
  print('Analyzing: $url');

  try {
    final html = await _fetchHtml(url);
    final framework = _detectFramework(html, url);

    if (framework == null) {
      print('Could not detect framework for $url');
      print('Detected signatures:');
      _printSignatures(html);
      exit(1);
    }

    print('Detected framework: $framework');

    final siteName = _extractSiteName(html, url);
    final lang = _detectLanguage(html, url);
    final slug = _slugify(siteName);
    final id = '$slug-$lang';

    print('Site name: $siteName');
    print('Language: $lang');
    print('Source ID: $id');

    // Create source directory and source.json
    final sourceDir =
        'dart/manga/multisrc/$framework/src/$lang/$slug';
    await Directory(sourceDir).create(recursive: true);

    final sourceJson = {
      'id': id,
      'name': siteName,
      'baseUrl': url,
      'lang': lang,
      'framework': framework,
      'sourceCodeLanguage': 'dart',
      'version': '0.1.0',
      'isNsfw': false,
      'hasCloudflare': _hasCloudflare(html),
      'dateFormat': _guessDateFormat(framework, lang),
      'dateFormatLocale': '${lang}_${lang == 'en' ? 'us' : lang}',
    };

    final sourceFile = File('$sourceDir/source.json');
    await sourceFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(sourceJson),
    );

    print('\nCreated: $sourceDir/source.json');
    print('Run "dart run source_generator.dart" to regenerate index.json');
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

Future<String> _fetchHtml(String url) async {
  final client = HttpClient();
  client.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return body;
  } finally {
    client.close();
  }
}

String? _detectFramework(String html, String url) {
  final htmlLower = html.toLowerCase();

  // Madara detection
  if (_isMadara(htmlLower)) return 'madara';

  // MangaThemesia detection
  if (_isMangaThemesia(htmlLower)) return 'mangathemesia';

  // MangaBox detection
  if (_isMangaBox(htmlLower)) return 'mangabox';

  // MMRCMS detection
  if (_isMMRCMS(htmlLower)) return 'mmrcms';

  return null;
}

bool _isMadara(String html) {
  int score = 0;
  if (html.contains('madara')) score += 3;
  if (html.contains('wp-manga')) score += 3;
  if (html.contains('manga_get_chapters')) score += 3;
  if (html.contains('wp-content/themes/flavor') ||
      html.contains('flavor-flavor')) score += 2;
  if (html.contains('div class="page-item-detail"')) score += 2;
  if (html.contains('manga__item')) score += 2;
  if (html.contains('m_orderby')) score += 2;
  if (html.contains('wp-admin/admin-ajax.php')) score += 1;
  return score >= 4;
}

bool _isMangaThemesia(String html) {
  int score = 0;
  if (html.contains('class="bsx"') || html.contains('class="bs"')) score += 3;
  if (html.contains('class="listupd"')) score += 2;
  if (html.contains('seriestuontent') || html.contains('seriestucontent')) score += 3;
  if (html.contains('themesia') || html.contains('flavor-flavor-flavor')) score += 2;
  if (html.contains('id="chapterlist"')) score += 2;
  if (html.contains('class="chapternum"')) score += 2;
  if (html.contains('id="readerarea"')) score += 3;
  return score >= 4;
}

bool _isMangaBox(String html) {
  int score = 0;
  if (html.contains('panel-story-list')) score += 3;
  if (html.contains('story-item') || html.contains('story_item')) score += 2;
  if (html.contains('container-chapter-reader')) score += 3;
  if (html.contains('content-genres-item')) score += 2;
  if (html.contains('panel-story-info-description')) score += 2;
  return score >= 4;
}

bool _isMMRCMS(String html) {
  int score = 0;
  if (html.contains('my-manga-reader-cms')) score += 5;
  if (html.contains('/filterList?')) score += 3;
  if (html.contains('img-responsive')) score += 1;
  return score >= 4;
}

String _extractSiteName(String html, String url) {
  // Try <title> tag
  final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true)
      .firstMatch(html);
  if (titleMatch != null) {
    var title = titleMatch.group(1)!.trim();
    // Clean common suffixes
    title = title
        .replaceAll(RegExp(r'\s*[-–|]\s*Read.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-–|]\s*Free.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-–|]\s*Online.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[-–|]\s*Manga.*', caseSensitive: false), '')
        .trim();
    if (title.isNotEmpty && title.length < 50) return title;
  }

  // Fall back to domain name
  final uri = Uri.parse(url);
  return uri.host
      .replaceAll(RegExp(r'^www\.'), '')
      .split('.')
      .first
      .replaceAll('-', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _detectLanguage(String html, String url) {
  // Check html lang attribute
  final langMatch =
      RegExp(r'<html[^>]+lang="([a-z]{2})', caseSensitive: false)
          .firstMatch(html);
  if (langMatch != null) return langMatch.group(1)!.toLowerCase();

  // Check URL for language hints
  final uri = Uri.parse(url);
  final tld = uri.host.split('.').last;
  final tldLangMap = {
    'jp': 'ja', 'kr': 'ko', 'cn': 'zh', 'fr': 'fr',
    'de': 'de', 'es': 'es', 'it': 'it', 'br': 'pt',
    'ru': 'ru', 'th': 'th', 'id': 'id', 'tr': 'tr',
  };
  if (tldLangMap.containsKey(tld)) return tldLangMap[tld]!;

  return 'en';
}

bool _hasCloudflare(String html) {
  return html.contains('cf-browser-verification') ||
      html.contains('cloudflare') ||
      html.contains('cf_chl_opt');
}

String _guessDateFormat(String framework, String lang) {
  switch (framework) {
    case 'madara':
      return 'MMMM dd, yyyy';
    case 'mangathemesia':
      return 'MMMM dd, yyyy';
    case 'mangabox':
      return 'MMM dd,yyyy';
    default:
      return 'yyyy-MM-dd';
  }
}

String _slugify(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'[\s-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

void _printSignatures(String html) {
  final checks = {
    'Madara: wp-manga': html.contains('wp-manga'),
    'Madara: madara keyword': html.contains('madara'),
    'MangaThemesia: bsx class': html.contains('class="bsx"'),
    'MangaThemesia: listupd': html.contains('class="listupd"'),
    'MangaThemesia: readerarea': html.contains('id="readerarea"'),
    'MangaBox: panel-story-list': html.contains('panel-story-list'),
    'MangaBox: container-chapter-reader':
        html.contains('container-chapter-reader'),
    'MMRCMS: my-manga-reader-cms': html.contains('my-manga-reader-cms'),
    'Cloudflare: detected': html.contains('cloudflare'),
  };
  for (final entry in checks.entries) {
    if (entry.value) print('  ✓ ${entry.key}');
  }
}
