import 'package:flutter/material.dart';

class Order {
  final int id;
  final String? name;
  final String? phone;
  final String? address;
  final int? kg;
  final int? cod;
  final int? status;
  final String? date;
  final String? orderid;
  final String? realorderid;
  final int? khid;
  final int? statuscode;
  final String? statustext;
  final String? realfbid;
  final String? userid;
  final String? pageid;
  final String? time;
  final String? shipperName;
  final String? shipperPhone;
  final String? lastUpdate;

  Order({
    required this.id,
    this.name,
    this.phone,
    this.address,
    this.kg,
    this.cod,
    this.status,
    this.date,
    this.orderid,
    this.realorderid,
    this.khid,
    this.statuscode,
    this.statustext,
    this.realfbid,
    this.userid,
    this.pageid,
    this.time,
    this.shipperName,
    this.shipperPhone,
    this.lastUpdate,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] ?? 0,
        name: j['name'],
        phone: j['phone'],
        address: j['address'],
        kg: j['kg'],
        cod: j['cod'],
        status: j['status'],
        date: j['date'],
        orderid: j['orderid'],
        realorderid: j['realorderid'],
        khid: j['khid'],
        statuscode: j['statuscode'],
        statustext: j['statustext'],
        realfbid: j['realfbid'],
        userid: j['userid'],
        pageid: j['pageid'],
        time: j['time'],
        shipperName: j['shipper_name'],
        shipperPhone: j['shipper_phone'],
        lastUpdate: j['last_update'],
      );

  static const Map<int, String> statusMap = {
    -108: 'Mới tạo',
    100: 'Mới tạo',
    101: 'ViettelPost yêu cầu hủy',
    102: 'Chờ bưu tá nhận hàng',
    103: 'Giao bưu cục nhận hàng',
    104: 'Giao bưu tá đi nhận',
    105: 'Bưu tá đã nhận hàng',
    106: 'Đối tác yêu cầu lấy lại',
    107: 'Đơn hàng đã hủy',
    200: 'Nhận từ bưu tá - Bưu cục gốc',
    201: 'Hủy nhập phiếu gửi',
    202: 'Sửa phiếu gửi',
    300: 'Đang vận chuyển',
    301: 'Đóng túi gói',
    302: 'Đóng chuyến thư',
    303: 'Đóng tuyến xe',
    400: 'Nhận bảng kê đến',
    401: 'Nhận túi gói',
    402: 'Nhận chuyến thư',
    403: 'Nhận chuyến xe',
    500: 'Giao bưu tá đi phát',
    501: 'Phát thành công',
    502: 'Chuyển hoàn bưu cục gốc',
    503: 'Hủy - Theo yêu cầu KH',
    504: 'Hoàn thành công',
    505: 'Tồn - Thông báo chuyển hoàn',
    506: 'Tồn - Khách không có nhà',
    507: 'Tồn - KH đến bưu cục nhận',
    508: 'Đơn vị yêu cầu phát tiếp',
    509: 'Chuyển tiếp bưu cục khác',
    510: 'Hủy phân công phát',
    515: 'Bưu cục phát duyệt hoàn',
    550: 'KH yêu cầu phát tiếp',
    551: 'Đang chuyển hoàn',
  };

  String get displayStatus {
    if (statuscode == null) return statustext ?? 'Không rõ';
    return statusMap[statuscode!] ?? statustext ?? 'Mã $statuscode';
  }

  static Color statusColor(int? code) {
    if (code == null) return const Color(0xFFB0B3B8);
    if (code == 501) {
      return const Color(0xFF42B72A); // Phát thành công → xanh lá
    }
    if (code == 107 || code == 503) return const Color(0xFFB0B3B8); // Hủy → xám
    if (code == 502 || code == 504 || code == 551) {
      return Colors.red; // Hoàn + đang chuyển hoàn → đỏ
    }
    if (code == 505 || code == 506 || code == 507) {
      return const Color.fromARGB(255, 197, 130, 4); // Tồn (có vấn đề) → cam
    }
    if (code >= 500) return const Color(0xFF1877F2); // Đang phát → xanh dương
    if (code >= 300) return const Color(0xFF00BCD4); // Vận chuyển → cyan
    if (code >= 200) return const Color(0xFF9C27B0); // Nhận hàng → tím
    if (code >= 100) {
      return const Color.fromARGB(255, 233, 219, 31); // Mới tạo → cam
    }
    return const Color(0xFFB0B3B8);
  }

  Color get color => statusColor(statuscode);

  String get codFormatted {
    if (cod == null) return '0đ';
    final v = cod!;
    final str = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '$bufđ';
  }
}
