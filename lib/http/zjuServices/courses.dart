// This implementation is adapted from the project "login-ZJU" by 5dbwat4(https://github.com/5dbwat4/login-ZJU) under the MIT License.
// See: https://github.com/5dbwat4/login-ZJU/blob/main/src/utils/fetch-with-cookie.ts

import 'dart:convert';
import 'dart:io';

import 'package:litechron/database/database_helper.dart';
import 'package:litechron/http/zjuServices/exceptions.dart';
import 'package:litechron/utils/tuple.dart';
import 'package:litechron/model/todo.dart';

class Courses {
  static final Uri _todoUri = Uri.parse("https://courses.zju.edu.cn/api/todos");

  DatabaseHelper? _db;
  Cookie? _session;
  Cookie? _iPlanetDirectoryPro;
  Future<void>? _loginFuture;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  Future<Tuple<Exception?, List<Todo>>> getTodo(HttpClient httpClient) async {
    try {
      var session = await _requireSession(httpClient);
      var body = await _requestTodo(httpClient, session);

      if (_isLoginPage(body)) {
        // 会话失效：并发的登录若已换了新会话就直接用，否则重登一次
        if (identical(_session, session)) {
          await _relogin(httpClient);
        }
        session = await _requireSession(httpClient);
        body = await _requestTodo(httpClient, session);
      }
      if (_isLoginPage(body)) {
        throw ExceptionWithMessage("未登录");
      }

      final todosJson = jsonDecode(body) as Map<String, dynamic>;
      _db?.setCachedWebPage("courses_todo", body);

      return Tuple(null, Todo.getAllFromCourses(todosJson));
    } catch (e) {
      var exception = _toException(e);
      return Tuple(exception, _getCachedTodos());
    }
  }

  /// 登录学在浙大。已有登录进行中时直接等待它完成，不并发建立第二个会话
  Future<bool> login(HttpClient httpClient, Cookie? iPlanetDirectoryPro) async {
    if (iPlanetDirectoryPro == null) {
      throw ExceptionWithMessage("iPlanetDirectoryPro无效");
    }
    _iPlanetDirectoryPro = iPlanetDirectoryPro;

    final inFlight = _loginFuture;
    if (inFlight != null) {
      await inFlight;
      return true;
    }
    final future = _doLogin(httpClient, iPlanetDirectoryPro);
    _loginFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loginFuture, future)) {
        _loginFuture = null;
      }
    }
    return true;
  }

  Future<void> _doLogin(
      HttpClient httpClient, Cookie iPlanetDirectoryPro) async {
    late HttpClientRequest request;
    late HttpClientResponse response;
    Cookie? session;

    var cookies = <Cookie>[iPlanetDirectoryPro];

    Future<void> getWithCookies(String url) async {
      request = await httpClient.getUrl(Uri.parse(url)).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"),
          );
      request.followRedirects = false;
      request.cookies.addAll(cookies);
      response = await request.close().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw ExceptionWithMessage("请求超时"),
          );
      cookies.addAll(response.cookies);
      response.drain();
      if (response.isRedirect) {
        if (response.headers.value(HttpHeaders.locationHeader)! ==
            ("https://courses.zju.edu.cn/user/index")) {
          session = response.cookies.firstWhere(
            (cookie) => cookie.name == "session",
          );
          return;
        }
        return await getWithCookies(
          response.headers.value(HttpHeaders.locationHeader) as String,
        );
      }
    }

    await getWithCookies("https://courses.zju.edu.cn/user/index");
    if (session == null) {
      throw ExceptionWithMessage("无法获取session");
    }
    // 登录成功后才替换，并发中的请求继续用各自取到的旧会话
    _session = session;
  }

  void logout() {
    _session = null;
    _iPlanetDirectoryPro = null;
    _loginFuture = null;
  }

  Future<void> _relogin(HttpClient httpClient) async {
    final iPlanetDirectoryPro = _iPlanetDirectoryPro;
    if (iPlanetDirectoryPro == null) {
      throw ExceptionWithMessage("未登录");
    }
    await login(httpClient, iPlanetDirectoryPro);
  }

  /// 当前会话 Cookie；没有时用 SSO 凭据重登取一个
  Future<Cookie> _requireSession(HttpClient httpClient) async {
    final session = _session;
    if (session != null) return session;
    await _relogin(httpClient);
    return _session ?? (throw ExceptionWithMessage("未登录"));
  }

  Future<String> _requestTodo(HttpClient httpClient, Cookie session) async {
    final request = await httpClient.getUrl(_todoUri).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw ExceptionWithMessage("请求超时"),
        );
    request.cookies.add(session);
    final response = await request.close().timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw ExceptionWithMessage("请求超时"),
        );

    return await response.transform(utf8.decoder).join();
  }

  bool _isLoginPage(String body) {
    return body.contains("cas/login") || body.contains("统一身份认证");
  }

  List<Todo> _getCachedTodos() {
    try {
      final cached = _db?.getCachedWebPage("courses_todo");
      if (cached == null) return [];

      return Todo.getAllFromCourses(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return [];
    }
  }

  Exception _toException(Object error) {
    if (error is SocketException) return ExceptionWithMessage("网络错误");
    if (error is Exception) return error;
    return ExceptionWithMessage(error.toString());
  }
}
