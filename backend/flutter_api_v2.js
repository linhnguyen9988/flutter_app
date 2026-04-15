// ============================================================
// THÊM VÀO flutter_api.js - Auth, Dashboard, Orders, FCM Push
// ============================================================
// npm install jsonwebtoken bcryptjs firebase-admin
// ============================================================

const express = require('express');
const router = express.Router();
const db = require('./db');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-this';

// ─── MIDDLEWARE: xác thực JWT ─────────────────────────────────
const authMiddleware = (req, res, next) => {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    req.user = jwt.verify(auth.slice(7), JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'Token không hợp lệ' });
  }
};

// ─── AUTH ─────────────────────────────────────────────────────

// POST /api/auth/login
router.post('/auth/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ message: 'Thiếu username hoặc password' });
  }
  try {
    const [[user]] = await db.query(
      `SELECT * FROM users WHERE username = ?`, [username]
    );
    if (!user) return res.status(401).json({ message: 'Tài khoản không tồn tại' });

    // So sánh password (hỗ trợ cả plain text và bcrypt)
    let valid = false;
    if (user.password.startsWith('$2')) {
      valid = await bcrypt.compare(password, user.password);
    } else {
      valid = password === user.password; // plain text fallback
    }
    if (!valid) return res.status(401).json({ message: 'Mật khẩu không đúng' });

    const token = jwt.sign(
      { id: user.id, username: user.username },
      JWT_SECRET,
      { expiresIn: '30d' }
    );
    res.json({
      token,
      user: { id: user.id, username: user.username, fullname: user.fullname }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── DASHBOARD ────────────────────────────────────────────────

// GET /api/dashboard/stats
router.get('/dashboard/stats', authMiddleware, async (req, res) => {
  try {
    const [[{ totalMessages }]] = await db.query(`SELECT COUNT(*) as totalMessages FROM messaging`);
    const [[{ unreadMessages }]] = await db.query(`SELECT COUNT(*) as unreadMessages FROM messaging WHERE isread = 0`);
    const [[{ totalCustomers }]] = await db.query(`SELECT COUNT(*) as totalCustomers FROM khachhang`);
    const [[{ newCustomersToday }]] = await db.query(
      `SELECT COUNT(*) as newCustomersToday FROM khachhang WHERE DATE(joindate) = CURDATE()`
    );
    const [[{ totalOrders }]] = await db.query(`SELECT COUNT(*) as totalOrders FROM lendon`);
    const [[{ pendingOrders }]] = await db.query(`SELECT COUNT(*) as pendingOrders FROM lendon WHERE statuscode = 0`);
    const [[{ deliveredOrders }]] = await db.query(`SELECT COUNT(*) as deliveredOrders FROM lendon WHERE statuscode = 2`);
    const [[{ cancelledOrders }]] = await db.query(`SELECT COUNT(*) as cancelledOrders FROM lendon WHERE statuscode = -1`);
    const [[{ totalCod }]] = await db.query(`SELECT COALESCE(SUM(cod), 0) as totalCod FROM lendon WHERE statuscode = 2`);
    const [[{ totalLiveComments }]] = await db.query(`SELECT COUNT(*) as totalLiveComments FROM livecomment`);

    // 7 ngày gần đây
    const [last7Days] = await db.query(`
      SELECT 
        DATE_FORMAT(d.date, '%Y-%m-%d') as date,
        COALESCE(m.cnt, 0) as messages,
        COALESCE(o.cnt, 0) as orders,
        COALESCE(c.cnt, 0) as customers
      FROM (
        SELECT CURDATE() - INTERVAL n DAY as date
        FROM (SELECT 0 n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) nums
      ) d
      LEFT JOIN (SELECT DATE(FROM_UNIXTIME(timestamp/1000)) as dt, COUNT(*) as cnt FROM messaging GROUP BY dt) m ON m.dt = d.date
      LEFT JOIN (SELECT DATE(last_update) as dt, COUNT(*) as cnt FROM lendon GROUP BY dt) o ON o.dt = d.date
      LEFT JOIN (SELECT DATE(joindate) as dt, COUNT(*) as cnt FROM khachhang GROUP BY dt) c ON c.dt = d.date
      ORDER BY d.date ASC
    `);

    res.json({
      totalMessages, unreadMessages, totalCustomers, newCustomersToday,
      totalOrders, pendingOrders, deliveredOrders, cancelledOrders,
      totalCod: parseInt(totalCod),
      totalLiveComments,
      last7Days
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── ORDERS ───────────────────────────────────────────────────

// GET /api/orders
router.get('/orders', authMiddleware, async (req, res) => {
  const { status, search, limit = 50, offset = 0 } = req.query;
  try {
    let sql = `SELECT * FROM lendon WHERE 1=1`;
    const params = [];
    if (status !== undefined && status !== '') {
      sql += ` AND statuscode = ?`;
      params.push(parseInt(status));
    }
    if (search) {
      sql += ` AND (name LIKE ? OR phone LIKE ? OR orderid LIKE ? OR realorderid LIKE ?)`;
      params.push(`%${search}%`, `%${search}%`, `%${search}%`, `%${search}%`);
    }
    sql += ` ORDER BY last_update DESC LIMIT ? OFFSET ?`;
    params.push(parseInt(limit), parseInt(offset));
    const [rows] = await db.query(sql, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/orders/:id
router.get('/orders/:id', authMiddleware, async (req, res) => {
  try {
    const [[row]] = await db.query(`SELECT * FROM lendon WHERE id = ?`, [req.params.id]);
    if (!row) return res.status(404).json({ error: 'Không tìm thấy' });
    res.json(row);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/orders/:id/status
router.put('/orders/:id/status', authMiddleware, async (req, res) => {
  const { statusCode, statusText } = req.body;
  try {
    await db.query(
      `UPDATE lendon SET statuscode = ?, statustext = ?, last_update = NOW() WHERE id = ?`,
      [statusCode, statusText, req.params.id]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── PUSH NOTIFICATION (FCM) ──────────────────────────────────
// Thêm vào webhook handler để gửi push khi có tin nhắn mới

/*
// Cài: npm install firebase-admin
// Setup: Tải service account key từ Firebase Console

const admin = require('firebase-admin');
const serviceAccount = require('./firebase-service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

// Gọi hàm này trong webhook handler khi nhận tin nhắn mới
async function sendPushNotification(senderName, messageText, recipientPageId) {
  try {
    // Lấy tất cả FCM tokens của admin users
    const [tokens] = await db.query(`SELECT token FROM usertoken`);
    if (!tokens.length) return;

    const message = {
      notification: {
        title: `💬 ${senderName}`,
        body: messageText.length > 100 ? messageText.substring(0, 100) + '...' : messageText,
      },
      data: {
        type: 'new_message',
        sender: senderName,
        pageId: recipientPageId,
      },
      tokens: tokens.map(t => t.token),
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Push sent: ${response.successCount} success, ${response.failureCount} failed`);
  } catch (err) {
    console.error('Push error:', err);
  }
}

// POST /api/fcm/token - lưu FCM token từ app
router.post('/fcm/token', authMiddleware, async (req, res) => {
  const { token } = req.body;
  try {
    await db.query(
      `INSERT INTO usertoken (token) VALUES (?) ON DUPLICATE KEY UPDATE token = VALUES(token)`,
      [token]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});
*/

// ─── MESSAGES & OTHERS (giữ nguyên từ flutter_api.js cũ) ─────
// ... (copy toàn bộ routes từ flutter_api.js cũ vào đây)

module.exports = router;
