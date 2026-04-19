import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/customer.dart';
import '../models/live_comment.dart';
import '../models/order.dart';

class ApiService {
  static const String baseUrl = 'http://aodaigiabao.com:3000/api';

  static String _token = '';
  static void setToken(String token) => _token = token;
  static String get token => _token;

  static String _userId = '';
  static void setUserId(String id) => _userId = id;
  static String get userId => _userId;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  static Future<List<Message>> getMessages({
    String? sender,
    String? pageId,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (sender != null) 'sender': sender,
      if (pageId != null) 'pageId': pageId,
    };
    final uri = Uri.parse('$baseUrl/messages').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => Message.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải tin nhắn: ${res.statusCode}');
  }

  static Future<
          ({
            List<Message> messages,
            int readWatermark,
            Map<String, String> reactions
          })>
      getConversation(String sender, {int limit = 20, int offset = 0}) async {
    final uri = Uri.parse('$baseUrl/messages/conversation/$sender')
        .replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final body = json.decode(utf8.decode(res.bodyBytes));
      if (body is List) {
        return (
          messages: body.map((e) => Message.fromJson(e)).toList(),
          readWatermark: 0,
          reactions: <String, String>{},
        );
      }
      final msgs =
          (body['messages'] as List).map((e) => Message.fromJson(e)).toList();
      final wm = body['readWatermark'] ?? 0;
      final rxList = body['reactions'] as List? ?? [];
      final reactions = <String, String>{
        for (final r in rxList)
          r['messid'].toString(): r['reaction_emoji'].toString()
      };
      return (messages: msgs, readWatermark: wm as int, reactions: reactions);
    }
    throw Exception('Lỗi tải cuộc hội thoại');
  }

  static Future<bool> sendMessage({
    required String recipient,
    required String message,
    required String pageId,
    File? imageFile,
  }) async {
    final uri = Uri.parse('$baseUrl/messages/send');
    final request = http.MultipartRequest('POST', uri);

    if (_token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }

    request.fields['recipient'] = recipient;
    request.fields['message'] = message;
    request.fields['currentPageID'] = pageId;

    if (imageFile != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ));
    }

    final streamed = await request.send();
    return streamed.statusCode == 200;
  }

  static Future<bool> markAsRead(int id) async {
    final uri = Uri.parse('$baseUrl/messages/$id/read');
    final res = await http.put(uri, headers: _headers);
    return res.statusCode == 200;
  }

  static Future<void> markAllAsRead(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final uri = Uri.parse('$baseUrl/messages/read-batch');
      await http.put(uri, headers: _headers, body: json.encode({'ids': ids}));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getRecentLivestreams(
      {int limit = 5}) async {
    final uri = Uri.parse('$baseUrl/livecomments/livestreams?limit=$limit');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Lỗi tải livestreams');
  }

  static Future<List<LiveComment>> getLiveComments({
    String? liveId,
    String? pageId,
    int? limit,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'offset': offset.toString(),
      if (limit != null) 'limit': limit.toString(),
      if (liveId != null) 'liveId': liveId,
      if (pageId != null) 'pageId': pageId,
    };
    final uri =
        Uri.parse('$baseUrl/livecomments').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => LiveComment.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải bình luận live');
  }

  static Future<List<Customer>> getCustomers({
    String? pageId,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (pageId != null) 'pageId': pageId,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri =
        Uri.parse('$baseUrl/customers').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => Customer.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải khách hàng');
  }

  static Future<Customer?> getCustomerById(int id) async {
    final uri = Uri.parse('$baseUrl/customers/$id');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      return Customer.fromJson(json.decode(utf8.decode(res.bodyBytes)));
    }
    return null;
  }

  static Future<bool> updateCustomer(int id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/customers/$id');
    final res = await http.put(uri, headers: _headers, body: json.encode(data));
    return res.statusCode == 200;
  }

  static List<Order> _sortOrders(List<Order> orders) {
    orders.sort((a, b) {
      final tA = a.time ?? a.date ?? '';
      final tB = b.time ?? b.date ?? '';
      final timeCmp = tB.compareTo(tA); // DESC
      if (timeCmp != 0) return timeCmp;
      final cA = a.statuscode ?? 0;
      final cB = b.statuscode ?? 0;
      if (cA < 500 && cB < 500) return cB.compareTo(cA);
      return cB.compareTo(cA);
    });
    return orders;
  }

  static Future<List<Order>> getUserOrders(String userid) async {
    final uri = Uri.parse('https://aodaigiabao.com/getuserorder');
    final res = await http.post(
      uri,
      headers: _headers,
      body: json.encode({'userid': userid}),
    );
    if (res.statusCode == 200) {
      final body = json.decode(utf8.decode(res.bodyBytes));
      final List data = body['data'] ?? [];
      return _sortOrders(data.map((e) => Order.fromJson(e)).toList());
    }
    throw Exception('Lỗi tải đơn hàng: ${res.statusCode}');
  }

  static Future<List<Order>> getOrders({
    String? status,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (status != null) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse('$baseUrl/orders').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return _sortOrders(data.map((e) => Order.fromJson(e)).toList());
    }
    throw Exception('Lỗi tải đơn hàng');
  }

  static Future<Order?> getOrderById(int id) async {
    final uri = Uri.parse('$baseUrl/orders/$id');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      return Order.fromJson(json.decode(utf8.decode(res.bodyBytes)));
    }
    return null;
  }

  static Future<bool> updateOrderStatus(
      int id, int statusCode, String statusText) async {
    final uri = Uri.parse('$baseUrl/orders/$id/status');
    final res = await http.put(
      uri,
      headers: _headers,
      body: json.encode({'statusCode': statusCode, 'statusText': statusText}),
    );
    return res.statusCode == 200;
  }

  static Future<List<Map<String, dynamic>>> getOrderLogs(
      String orderNumber) async {
    final uri = Uri.parse('$baseUrl/orders/logs/$orderNumber');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Lỗi tải hành trình đơn');
  }

  static Future<List<PageInfo>> getPages() async {
    final uri = Uri.parse('$baseUrl/pages');
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode == 200) {
      final List data = json.decode(utf8.decode(res.bodyBytes));
      return data.map((e) => PageInfo.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải danh sách page');
  }

  static Future<String> getPageIdByUserid(String userid) async {
    try {
      final uri = Uri.parse('$baseUrl/customers/pageid/$userid');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        return data['pageid']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  static Future<List<Map<String, dynamic>>> getCustomerLiveChots({
    required String userid,
    required List<String> liveIds,
  }) async {
    if (userid.isEmpty || liveIds.isEmpty) return [];
    try {
      final uri = Uri.parse('$baseUrl/livecomments/customer-chots');
      final res = await http.post(
        uri,
        headers: _headers,
        body: json.encode({'userid': userid, 'liveIds': liveIds}),
      );
      if (res.statusCode == 200) {
        final body = json.decode(utf8.decode(res.bodyBytes));
        final List data = body['chots'] ?? body ?? [];
        return data.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> postRaw(
      String url, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse(url);
      final res = await http.post(uri,
          headers: {
            'Content-Type': 'application/json',
            if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
          },
          body: json.encode(body));
      if (res.statusCode == 200) {
        return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      return {'error': 'HTTP ${res.statusCode}'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
