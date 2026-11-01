import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 轻量 WebDAV 客户端（基于 dart:io HttpClient，无第三方依赖）。
/// 支持：测试连接、自动建目录、上传备份、列出备份、下载备份。
class WebDavClient {
  final String baseUrl; // 服务器 URL，如 https://dav.jianguoyun.com/dav/
  final String username;
  final String password;
  final String folder; // 同步文件夹路径，如 /PomodoroData/

  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.folder = '/PomodoroData/',
  });

  // ---------- URL / 认证 ----------

  String get _base {
    var b = baseUrl.trim();
    if (b.isEmpty) throw const WebDavException('服务器 URL 不能为空');
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      throw const WebDavException('URL 需以 http:// 或 https:// 开头');
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  String get _dir {
    var p = folder.trim();
    if (p.isEmpty || p == '/') p = '/PomodoroData/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return '$p/';
  }

  Uri _uri(String sub) => Uri.parse('$_base$_dir$sub');

  /// 发起请求并完整读取响应，返回 (状态码, 响应文本)
  Future<(int, String)> _request(String method, Uri uri, {String? body}) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.openUrl(method, uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64Encode(utf8.encode('$username:$password'))}');
      if (body != null) {
        req.headers.contentType = ContentType.text;
        req.add(utf8.encode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await utf8.decoder.bind(res).join();
      return (res.statusCode, text);
    } on SocketException catch (e) {
      throw WebDavException('网络连接失败：${e.message}');
    } on TimeoutException {
      throw const WebDavException('连接超时，请检查服务器地址');
    } finally {
      c.close(force: true);
    }
  }

  /// 统一状态码检查，401/403 给出明确提示
  void _check(int status, String action, {Set<int> ok = const {200, 201, 204}}) {
    if (status == 401 || status == 403) {
      throw const WebDavException('账号或密码错误（401），部分网盘需使用"应用密码"');
    }
    if (!ok.contains(status)) {
      throw WebDavException('$action失败（HTTP $status）');
    }
  }

  // ---------- 对外操作 ----------

  /// 测试连接：PROPFIND 目录；目录不存在时自动创建后再试
  Future<void> testConnection() async {
    var (status, _) = await _request('PROPFIND', _uri(''), body: _propfindBody);
    if (status == 404) {
      await ensureFolder();
      (status, _) = await _request('PROPFIND', _uri(''), body: _propfindBody);
    }
    _check(status, '测试连接', ok: {200, 207});
  }

  /// 确保远程目录存在（逐级 MKCOL）
  Future<void> ensureFolder() async {
    final parts = _dir.split('/')..removeWhere((e) => e.isEmpty);
    var path = '';
    for (final part in parts) {
      path += '/$part';
      final (status, _) = await _request('MKCOL', Uri.parse('$_base$path/'));
      // 201=创建成功 200/301/405=已存在或被重定向，均可继续
      if (status != 201 && status != 200 && status != 301 && status != 405) {
        throw WebDavException('创建目录失败（HTTP $status）');
      }
    }
  }

  /// 上传文本内容为一个备份文件
  Future<void> upload(String fileName, String content) async {
    await ensureFolder();
    final (status, _) = await _request('PUT', _uri(fileName), body: content);
    _check(status, '上传', ok: {200, 201, 204});
  }

  /// 列出目录下的 .json 备份文件名（按名称倒序 = 新的在前）
  Future<List<String>> listBackups() async {
    final (status, body) = await _request('PROPFIND', _uri(''), body: _propfindBody);
    _check(status, '获取列表', ok: {200, 207});
    final names = <String>{};
    final re = RegExp(r'<(?:[a-zA-Z0-9]+:)?href>\s*(.*?)\s*</(?:[a-zA-Z0-9]+:)?href>');
    for (final m in re.allMatches(body)) {
      final href = Uri.decodeComponent(m.group(1)!);
      final segs = href.split('/').where((e) => e.isNotEmpty).toList();
      if (segs.isEmpty) continue;
      final name = segs.last;
      if (name.toLowerCase().endsWith('.json')) names.add(name);
    }
    final list = names.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// 下载备份内容
  Future<String> download(String fileName) async {
    final (status, body) = await _request('GET', _uri(fileName));
    _check(status, '下载', ok: {200});
    return body;
  }
}

class WebDavException implements Exception {
  final String message;
  const WebDavException(this.message);
  @override
  String toString() => message;
}

const String _propfindBody =
    '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getlastmodified/></d:prop></d:propfind>';
