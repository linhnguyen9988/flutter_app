class Message {
  final int id;
  final String messid;
  final String sender;
  final String recipient;
  final String? message;
  final String? image;
  final String time;
  final int isRead;
  final int timestamp;
  final String? senderName;
  final List<dynamic>? reactions;
  bool readByCustomer;
  bool isPending;
  bool isFailed;

  Message({
    required this.id,
    required this.messid,
    required this.sender,
    required this.recipient,
    this.message,
    this.image,
    required this.time,
    required this.isRead,
    required this.timestamp,
    this.senderName,
    this.reactions,
    this.readByCustomer = false,
    this.isPending = false,
    this.isFailed = false,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] ?? 0,
        messid: j['messid'] ?? '',
        sender: j['sender'] ?? '',
        recipient: j['recipient'] ?? '',
        message: j['message'],
        image: j['image'],
        time: j['time'] ?? '',
        isRead: j['isread'] ?? 0,
        timestamp: j['timestamp'] ?? 0,
        senderName: j['fbname'] ?? j['senderName'],
        reactions: j['reaction'],
        readByCustomer: (j['isread'] ?? 0) == 1,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'messid': messid,
        'sender': sender,
        'recipient': recipient,
        'message': message,
        'image': image,
        'time': time,
        'isread': isRead,
        'timestamp': timestamp,
        'senderName': senderName,
        'reaction': reactions,
      };
  bool get hasImage => image != null && image!.isNotEmpty;
  bool get isUnread => isRead == 0;

  List<String> get imageList {
    if (image == null || image!.isEmpty) return [];
    return image!
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(
      timestamp > 9999999999 ? timestamp : timestamp * 1000);
}
