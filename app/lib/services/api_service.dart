import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String baseUrl = 'http://localhost:3000';

  static Future<void> initBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('apiBaseUrl');
    if (saved != null && saved.isNotEmpty) baseUrl = saved;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = url;
    await prefs.setString('apiBaseUrl', url);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String path) async {
    return await http.get(Uri.parse('$baseUrl$path'), headers: await _headers());
  }

  static Future<http.Response> post(String path, Map<String, dynamic> body) async {
    return await http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> put(String path, Map<String, dynamic> body) async {
    return await http.put(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> delete(String path) async {
    return await http.delete(Uri.parse('$baseUrl$path'), headers: await _headers());
  }

  static dynamic decode(http.Response res) {
    return jsonDecode(utf8.decode(res.bodyBytes));
  }
}
