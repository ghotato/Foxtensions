/// Source model for the extension repository.
/// Used by source_generator.dart to build index.json.
class Source {
  final String id;
  final String name;
  final String baseUrl;
  final String lang;
  final String framework;
  final String iconUrl;
  final String sourceCodeUrl;
  final String sourceCodeLanguage;
  final String version;
  final bool isNsfw;
  final bool hasCloudflare;
  final String dateFormat;
  final String dateFormatLocale;
  final String apiUrl;
  final String appMinVerReq;
  final Map<String, dynamic> config;
  final String notes;

  const Source({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.framework,
    this.iconUrl = '',
    required this.sourceCodeUrl,
    this.sourceCodeLanguage = 'dart',
    this.version = '0.1.0',
    this.isNsfw = false,
    this.hasCloudflare = false,
    this.dateFormat = '',
    this.dateFormatLocale = '',
    this.apiUrl = '',
    this.appMinVerReq = '0.0.1',
    this.config = const {},
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lang': lang,
        'framework': framework,
        'iconUrl': iconUrl,
        'sourceCodeUrl': sourceCodeUrl,
        'sourceCodeLanguage': sourceCodeLanguage,
        'version': version,
        'isNsfw': isNsfw,
        'hasCloudflare': hasCloudflare,
        'dateFormat': dateFormat,
        'dateFormatLocale': dateFormatLocale,
        'apiUrl': apiUrl,
        'appMinVerReq': appMinVerReq,
        'config': config,
        'notes': notes,
      };
}
