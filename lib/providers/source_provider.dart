// Defines App sources and provides functions used to interact with them
// AppSource is an abstract class with a concrete implementation for each source

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:http/http.dart';
import 'package:html/parser.dart';

class AppNames {
  late String author;
  late String name;

  AppNames(this.author, this.name);
}

class APKDetails {
  late String version;
  late List<String> apkUrls;

  APKDetails(this.version, this.apkUrls);
}

class App {
  late String id;
  late String url;
  late String author;
  late String name;
  String? installedVersion;
  late String latestVersion;
  List<String> apkUrls = [];
  late int preferredApkIndex;
  App(this.id, this.url, this.author, this.name, this.installedVersion,
      this.latestVersion, this.apkUrls, this.preferredApkIndex);

  @override
  String toString() {
    return 'ID: $id URL: $url INSTALLED: $installedVersion LATEST: $latestVersion APK: $apkUrls';
  }

  factory App.fromJson(Map<String, dynamic> json) => App(
        json['id'] as String,
        json['url'] as String,
        json['author'] as String,
        json['name'] as String,
        json['installedVersion'] == null
            ? null
            : json['installedVersion'] as String,
        json['latestVersion'] as String,
        List<String>.from(jsonDecode(json['apkUrls'])),
        json['preferredApkIndex'] == null
            ? 0
            : json['preferredApkIndex'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'author': author,
        'name': name,
        'installedVersion': installedVersion,
        'latestVersion': latestVersion,
        'apkUrls': jsonEncode(apkUrls),
        'preferredApkIndex': preferredApkIndex
      };
}

escapeRegEx(String s) {
  return s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (x) {
    return "\\${x[0]}";
  });
}

List<String> getLinksFromParsedHTML(
        Document dom, RegExp hrefPattern, String prependToLinks) =>
    dom
        .querySelectorAll('a')
        .where((element) {
          if (element.attributes['href'] == null) return false;
          return hrefPattern.hasMatch(element.attributes['href']!);
        })
        .map((e) => '$prependToLinks${e.attributes['href']!}')
        .toList();

abstract class AppSource {
  late String host;
  String standardizeURL(String url);
  Future<APKDetails> getLatestAPKDetails(String standardUrl);
  AppNames getAppNames(String standardUrl);
}

class GitHub implements AppSource {
  @override
  late String host = 'github.com';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res = await get(Uri.parse('$standardUrl/releases/latest'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var apkUrlList = getLinksFromParsedHTML(
          parsedHtml,
          RegExp(
              '^${escapeRegEx(standardUri.path)}/releases/download/[^/]+/[^/]+\\.apk\$',
              caseSensitive: false),
          standardUri.origin);
      if (apkUrlList.isEmpty) {
        throw 'No APK found';
      }
      String getTag(String url) {
        List<String> parts = url.split('/');
        return parts[parts.length - 2];
      }

      String latestTag = getTag(apkUrlList[0]);
      String? version = parsedHtml
          .querySelector('.octicon-tag')
          ?.nextElementSibling
          ?.innerHtml
          .trim();
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version,
          apkUrlList.where((element) => getTag(element) == latestTag).toList());
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    String temp = standardUrl.substring(standardUrl.indexOf('://') + 3);
    List<String> names = temp.substring(temp.indexOf('/') + 1).split('/');
    return AppNames(names[0], names[1]);
  }
}

class GitLab implements AppSource {
  @override
  late String host = 'gitlab.com';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res = await get(Uri.parse('$standardUrl/-/tags?format=atom'));
    if (res.statusCode == 200) {
      var standardUri = Uri.parse(standardUrl);
      var parsedHtml = parse(res.body);
      var entry = parsedHtml.querySelector('entry');
      var entryContent =
          parse(parseFragment(entry?.querySelector('content')!.innerHtml).text);
      var apkUrlList = getLinksFromParsedHTML(
          entryContent,
          RegExp(
              '^${escapeRegEx(standardUri.path)}/uploads/[^/]+/[^/]+\\.apk\$',
              caseSensitive: false),
          standardUri.origin);
      if (apkUrlList.isEmpty) {
        throw 'No APK found';
      }

      var entryId = entry?.querySelector('id')?.innerHtml;
      var version =
          entryId == null ? null : Uri.parse(entryId).pathSegments.last;
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version, apkUrlList);
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    // Same as GitHub
    return GitHub().getAppNames(standardUrl);
  }
}

class Signal implements AppSource {
  @override
  late String host = 'signal.org';

  @override
  String standardizeURL(String url) {
    return 'https://$host';
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res =
        await get(Uri.parse('https://updates.$host/android/latest.json'));
    if (res.statusCode == 200) {
      var json = jsonDecode(res.body);
      String? apkUrl = json['url'];
      if (apkUrl == null) {
        throw 'No APK found';
      }
      String? version = json['versionName'];
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version, [apkUrl]);
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) => AppNames('Signal', 'Signal');
}

class FDroid implements AppSource {
  @override
  late String host = 'f-droid.org';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host/[^/]+/packages/[^/]+');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res = await get(Uri.parse(standardUrl));
    if (res.statusCode == 200) {
      var latestReleaseDiv =
          parse(res.body).querySelector('#latest.package-version');
      var apkUrl = latestReleaseDiv
          ?.querySelector('.package-version-download a')
          ?.attributes['href'];
      if (apkUrl == null) {
        throw 'No APK found';
      }
      var version = latestReleaseDiv
          ?.querySelector('.package-version-header b')
          ?.innerHtml
          .split(' ')
          .last;
      if (version == null) {
        throw 'Could not determine latest release version';
      }
      return APKDetails(version, [apkUrl]);
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    var name = Uri.parse(standardUrl).pathSegments.last;
    return AppNames(name, name);
  }
}

class Mullvad implements AppSource {
  @override
  late String host = 'mullvad.net';

  @override
  String standardizeURL(String url) {
    RegExp standardUrlRegEx = RegExp('^https?://$host');
    RegExpMatch? match = standardUrlRegEx.firstMatch(url.toLowerCase());
    if (match == null) {
      throw 'Not a valid URL';
    }
    return url.substring(0, match.end);
  }

  @override
  Future<APKDetails> getLatestAPKDetails(String standardUrl) async {
    Response res = await get(Uri.parse('$standardUrl/en/download/android'));
    if (res.statusCode == 200) {
      var version = parse(res.body)
          .querySelector('p.subtitle.is-6')
          ?.querySelector('a')
          ?.attributes['href']
          ?.split('/')
          .last;
      if (version == null) {
        throw 'Could not determine the latest release version';
      }
      return APKDetails(
          version, ['https://mullvad.net/download/app/apk/latest']);
    } else {
      throw 'Unable to fetch release info';
    }
  }

  @override
  AppNames getAppNames(String standardUrl) {
    return AppNames('Mullvad-VPN', 'Mullvad-VPN');
  }
}

class SourceProvider {
  List<AppSource> sources = [GitHub(), GitLab(), FDroid(), Mullvad(), Signal()];

  // Add more source classes here so they are available via the service
  AppSource getSource(String url) {
    AppSource? source;
    for (var s in sources) {
      if (url.toLowerCase().contains('://${s.host}')) {
        source = s;
        break;
      }
    }
    if (source == null) {
      throw 'URL does not match a known source';
    }
    return source;
  }

  Future<App> getApp(String url) async {
    if (url.toLowerCase().indexOf('http://') != 0 &&
        url.toLowerCase().indexOf('https://') != 0) {
      url = 'https://$url';
    }
    if (url.toLowerCase().indexOf('https://www.') == 0) {
      url = 'https://${url.substring(12)}';
    }
    AppSource source = getSource(url);
    String standardUrl = source.standardizeURL(url);
    AppNames names = source.getAppNames(standardUrl);
    APKDetails apk = await source.getLatestAPKDetails(standardUrl);
    return App(
        '${names.author.toLowerCase()}_${names.name.toLowerCase()}_${source.host}',
        standardUrl,
        names.author[0].toUpperCase() + names.author.substring(1),
        names.name[0].toUpperCase() + names.name.substring(1),
        null,
        apk.version,
        apk.apkUrls,
        apk.apkUrls.length - 1);
  }

  List<String> getSourceHosts() => sources.map((e) => e.host).toList();
}
