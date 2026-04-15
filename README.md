# AD Gia Bảo - Flutter App

App quản lý tin nhắn Messenger và bình luận livestream Facebook.

## Cấu trúc project

```
lib/
├── main.dart
├── theme/
│   └── app_theme.dart
├── models/
│   ├── message.dart
│   ├── customer.dart
│   ├── live_comment.dart     # chứa cả PageInfo
│   └── page_info.dart
├── services/
│   └── api_service.dart
├── screens/
│   ├── splash_screen.dart
│   ├── home_screen.dart
│   ├── messaging_screen.dart
│   ├── chat_screen.dart
│   ├── live_comments_screen.dart
│   ├── customers_screen.dart
│   └── customer_detail_screen.dart
└── widgets/
    ├── page_filter_chip.dart
    └── avatar_widget.dart

backend/
└── flutter_api.js   ← thêm vào Node.js backend
```

## Tính năng

- ✅ Danh sách tin nhắn Messenger (group theo người gửi)
- ✅ Chat screen - xem & trả lời tin nhắn
- ✅ Bình luận livestream (filter chốt đơn)
- ✅ Danh sách khách hàng + chi tiết
- ✅ Filter theo Facebook Page
- ✅ Tìm kiếm
- ✅ Chỉnh sửa thông tin khách hàng (phone, địa chỉ, label, note, tag)
- ✅ Dark theme (Facebook style)

## Cài đặt

### 1. Flutter App

```bash
flutter pub get
flutter run
```

### 2. Cấu hình Backend URL

Mở `lib/services/api_service.dart` và đổi:
```dart
static const String baseUrl = 'http://YOUR_SERVER_IP:3000/api';
```

### 3. Thêm API vào Node.js backend

```javascript
// Trong file server.js / app.js chính của bạn:
const flutterApi = require('./flutter_api');
app.use('/api', flutterApi);
```

Đảm bảo file `db.js` export mysql2 connection pool:
```javascript
// db.js
const mysql = require('mysql2/promise');
const pool = mysql.createPool({
  host: 'localhost',
  user: 'root',
  password: 'YOUR_PASSWORD',
  database: 'YOUR_DATABASE',
});
module.exports = pool;
```

### 4. Cho phép CORS (nếu cần)

```javascript
const cors = require('cors');
app.use(cors());
```

## Android - Network Permission

Thêm vào `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Nếu dùng HTTP (không phải HTTPS), thêm:
```xml
<application android:usesCleartextTraffic="true" ...>
```

## iOS - Network Permission

Thêm vào `ios/Runner/Info.plist` nếu dùng HTTP:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```
