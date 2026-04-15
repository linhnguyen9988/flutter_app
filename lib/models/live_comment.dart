class LiveComment {
  final int idx;
  final String? commentid;
  final String? liveid;
  final String? userid;
  final String? name;
  final String? message;
  final String? chot;
  final String? gia;
  final String? timecomment;
  final String? datecreate;
  final int? luotin;
  final int? count;
  final String? pageid;
  final int? luotchot;
  final int? slchot;
  final String? avatarUrl; // từ socket emit (có link đầy đủ)
  final String?
      customerLabel; // label từ bảng khachhang: Bom hàng, Xả hàng, Có vấn đề
  final String? customerPhone; // phone từ bảng khachhang
  final String? nuocngoai; // 'Nước ngoài' nếu khách ở nước ngoài
  final int? khid; // id (cột tự tăng) trong bảng khachhang — dùng cho barcode
  final String? diachi; // địa chỉ khách (data[10])
  final String? note; // ghi chú live (data[19])
  final String? region; // nuocngoai dạng text (data[23])
  final String? fbnamex; // fbname từ bảng (data[15])

  LiveComment({
    required this.idx,
    this.commentid,
    this.liveid,
    this.userid,
    this.name,
    this.message,
    this.chot,
    this.gia,
    this.timecomment,
    this.datecreate,
    this.luotin,
    this.count,
    this.pageid,
    this.luotchot,
    this.slchot,
    this.avatarUrl,
    this.customerLabel,
    this.customerPhone,
    this.nuocngoai,
    this.khid,
    this.diachi,
    this.note,
    this.region,
    this.fbnamex,
  });

  factory LiveComment.fromJson(Map<String, dynamic> j) => LiveComment(
        idx: j['idx'] ?? 0,
        commentid: j['commentid'],
        liveid: j['liveid'],
        userid: j['userid'],
        name: j['name'],
        message: j['message'],
        chot: j['chot'],
        gia: j['gia'],
        timecomment: j['timecomment'],
        datecreate: j['datecreate'],
        luotin: j['luotin'],
        count: j['count'],
        pageid: j['pageid'],
        luotchot: j['luotchot'],
        slchot: j['slchot'],
        avatarUrl: j['avatarUrl'],
        customerLabel: j['customer_label'] ?? j['customerLabel'],
        customerPhone: j['customer_phone'] ?? j['customerPhone'],
        nuocngoai: j['nuocngoai'] ?? j['customer_nuocngoai'],
        khid: j['khid'] ?? j['customer_id'],
        diachi: j['diachi'],
        note: j['note'],
        region: j['region'] ?? j['nuocngoai'] ?? j['customer_nuocngoai'],
        fbnamex: j['fbnamex'],
      );

  // Tạo từ socket emit — data dạng newCommentData từ webhook
  factory LiveComment.fromSocket(Map<String, dynamic> d) => LiveComment(
        idx: d['idx'] ?? 0,
        commentid: d['cmtid'],
        liveid: d['liveid'],
        userid: d['customerInfo']?['userid'] ?? '',
        name: d['fbname'] ?? d['customerInfo']?['fbname'] ?? '',
        message: d['message'] ?? '',
        chot: d['customerInfo']?['chot'] ?? '',
        gia: d['customerInfo']?['gia'] ?? '',
        timecomment: d['timelocal'] ?? '',
        pageid: d['pageid'],
        avatarUrl: d['picture'] ?? d['customerInfo']?['avalink'],
        customerLabel: d['customerInfo']?['label'],
        customerPhone: d['customerInfo']?['phone'],
        nuocngoai: d['customerInfo']?['nuocngoai'] ?? d['nuocngoai'],
        diachi: d['customerInfo']?['diachi'] ?? d['diachi'],
        region:
            d['customerInfo']?['nuocngoai'] ?? d['nuocngoai'] ?? d['region'],
        khid: d['customerInfo']?['id'],
      );

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'commentid': commentid,
        'liveid': liveid,
        'userid': userid,
        'name': name,
        'message': message,
        'chot': chot,
        'gia': gia,
        'timecomment': timecomment,
        'datecreate': datecreate,
        'luotin': luotin,
        'count': count,
        'pageid': pageid,
        'luotchot': luotchot,
        'slchot': slchot,
        'avatarUrl': avatarUrl,
        'customer_label': customerLabel,
        'customer_phone': customerPhone,
        'nuocngoai': nuocngoai,
        'khid': khid,
        'diachi': diachi,
        'note': note,
        'region': region,
        'fbnamex': fbnamex,
      };

  bool get isAbroad => nuocngoai == 'Nước ngoài';

  bool get hasOrder {
    if (chot == null || chot!.isEmpty) return false;
    final v = chot!.trim().toUpperCase();
    return v == 'CHỐT' || v == 'CHOT';
  }

  // Avatar: ưu tiên link từ socket, fallback về link cố định theo userid
  String avatarUrlResolved(String baseAvaUrl) {
    if (avatarUrl != null && avatarUrl!.startsWith('http')) return avatarUrl!;
    if (userid != null && userid!.isNotEmpty) return '$baseAvaUrl/$userid.jpg';
    return '';
  }
}

class PageInfo {
  final int id;
  final String pageid;
  final String? name;
  final String? accesstoken;

  PageInfo({
    required this.id,
    required this.pageid,
    this.name,
    this.accesstoken,
  });

  factory PageInfo.fromJson(Map<String, dynamic> j) => PageInfo(
        id: j['id'] ?? 0,
        pageid: j['pageid'] ?? '',
        name: j['name'],
        accesstoken: j['accesstoken'],
      );

  String get displayName => name ?? pageid;
}
