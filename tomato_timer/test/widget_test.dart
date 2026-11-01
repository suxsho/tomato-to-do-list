import 'package:flutter_test/flutter_test.dart';

import 'package:tomato_timer/models.dart';
import 'package:tomato_timer/webdav.dart';

void main() {
  test('Settings 默认值：跟随系统主题 + WebDAV 未配置', () {
    final s = Settings();
    expect(s.themeMode, 'system');
    expect(s.soundOn, isTrue);
    expect(s.volume, 1.0);
    expect(s.webdavOn, isFalse);
    expect(s.webdavConfigured, isFalse);
  });

  test('Settings JSON 往返保留新增字段', () {
    final s = Settings(themeMode: 'dark', webdavOn: true, webdavUrl: 'https://dav.example.com/dav', webdavUser: 'u');
    final back = Settings.fromJson(s.toJson());
    expect(back.themeMode, 'dark');
    expect(back.webdavOn, isTrue);
    expect(back.webdavUrl, 'https://dav.example.com/dav');
    expect(back.webdavUser, 'u');
    expect(back.webdavConfigured, isTrue);
  });

  test('WebDavClient 配置校验', () {
    final bad = WebDavClient(baseUrl: '', username: 'u', password: 'p');
    expect(
      () async => bad.testConnection(),
      throwsA(isA<WebDavException>()),
    );
  });
}
