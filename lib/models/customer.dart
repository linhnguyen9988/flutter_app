class Customer {
  final int id;
  final String? userid;
  final String? fbname;
  final String? phone;
  final String? diachi;
  final String? avalink;
  final String? label;
  final String? pageid;
  final String? note;
  final String? psid;
  final String? tag;
  final String? joindate;
  final String? realfbid;
  final String? important;

  Customer({
    required this.id,
    this.userid,
    this.fbname,
    this.phone,
    this.diachi,
    this.avalink,
    this.label,
    this.pageid,
    this.note,
    this.psid,
    this.tag,
    this.joindate,
    this.realfbid,
    this.important,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] ?? 0,
        userid: j['userid'],
        fbname: j['fbname'],
        phone: j['phone'],
        diachi: j['diachi'],
        avalink: j['avalink'],
        label: j['label'],
        pageid: j['pageid'],
        note: j['note'],
        psid: j['psid'],
        tag: j['tag'],
        joindate: j['joindate'],
        realfbid: j['realfbid'],
        important: j['important'],
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'diachi': diachi,
        'label': label,
        'note': note,
        'tag': tag,
        'important': important,
      };

  String get displayName => fbname ?? userid ?? 'Khách hàng';
  bool get isImportant => important == '1' || important == 'true';

  Customer copyWith({
    String? phone,
    String? diachi,
    String? note,
    String? label,
    String? tag,
    String? important,
  }) =>
      Customer(
        id: id,
        userid: userid,
        fbname: fbname,
        phone: phone ?? this.phone,
        diachi: diachi ?? this.diachi,
        avalink: avalink,
        label: label ?? this.label,
        pageid: pageid,
        note: note ?? this.note,
        psid: psid,
        tag: tag ?? this.tag,
        joindate: joindate,
        realfbid: realfbid,
        important: important ?? this.important,
      );
}
