// ============================================================
// API ROUTES cho Flutter App - thêm vào Node.js backend
// ============================================================
// Cài đặt: npm install express mysql2
// Sử dụng: const apiRouter = require('./flutter_api');
//          app.use('/api', apiRouter);
// ============================================================

const express = require('express');
const router = express.Router();
const db = require('./db'); // pool mysql2 của bạn

// ─── MESSAGES ────────────────────────────────────────────────

// GET /api/messages - danh sách tin nhắn (group by sender)
router.get('/messages', async (req, res) => {
  const { pageId, sender, limit = 50, offset = 0 } = req.query;
  try {
    let sql = `SELECT * FROM messaging WHERE 1=1`;
    const params = [];
    if (pageId) {
      sql += ` AND (sender IN (SELECT pageid FROM pageinfo WHERE pageid=?) OR recipient IN (SELECT pageid FROM pageinfo WHERE pageid=?))`;
      params.push(pageId, pageId);
    }
    if (sender) {
      sql += ` AND sender = ?`;
      params.push(sender);
    }
    sql += ` ORDER BY timestamp DESC LIMIT ? OFFSET ?`;
    params.push(parseInt(limit), parseInt(offset));
    const [rows] = await db.query(sql, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/messages/conversation/:sender - toàn bộ cuộc hội thoại
router.get('/messages/conversation/:sender', async (req, res) => {
  const { sender } = req.params;
  try {
    const [rows] = await db.query(
      `SELECT * FROM messaging WHERE sender = ? OR recipient = ? ORDER BY timestamp ASC LIMIT 200`,
      [sender, sender]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/messages/send - gửi tin nhắn qua Facebook API
router.post('/messages/send', async (req, res) => {
  const { recipient, message, pageId } = req.body;
  if (!recipient || !message || !pageId) {
    return res.status(400).json({ error: 'Thiếu thông tin' });
  }
  try {
    // Lấy access token của page
    const [[page]] = await db.query(
      `SELECT accesstoken FROM pageinfo WHERE pageid = ?`, [pageId]
    );
    if (!page) return res.status(404).json({ error: 'Không tìm thấy page' });

    const fbRes = await fetch(
      `https://graph.facebook.com/v19.0/me/messages?access_token=${page.accesstoken}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          recipient: { id: recipient },
          message: { text: message }
        })
      }
    );
    const fbData = await fbRes.json();
    if (fbData.error) return res.status(400).json({ error: fbData.error.message });

    // Lưu vào DB
    await db.query(
      `INSERT INTO messaging (messid, sender, recipient, message, time, isread, timestamp)
       VALUES (?, ?, ?, ?, ?, 1, ?)`,
      [fbData.message_id || Date.now().toString(), pageId, recipient, message, 
       new Date().toISOString(), Date.now()]
    );
    res.json({ success: true, messageId: fbData.message_id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/messages/:id/read - đánh dấu đã đọc
router.put('/messages/:id/read', async (req, res) => {
  try {
    await db.query(`UPDATE messaging SET isread = 1 WHERE id = ?`, [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── LIVE COMMENTS ───────────────────────────────────────────

// GET /api/livecomments
router.get('/livecomments', async (req, res) => {
  const { liveId, pageId, limit = 100, offset = 0 } = req.query;
  try {
    let sql = `SELECT * FROM livecomment WHERE 1=1`;
    const params = [];
    if (liveId) { sql += ` AND liveid = ?`; params.push(liveId); }
    if (pageId) { sql += ` AND pageid = ?`; params.push(pageId); }
    sql += ` ORDER BY idx DESC LIMIT ? OFFSET ?`;
    params.push(parseInt(limit), parseInt(offset));
    const [rows] = await db.query(sql, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── CUSTOMERS ───────────────────────────────────────────────

// GET /api/customers
router.get('/customers', async (req, res) => {
  const { pageId, search, limit = 50, offset = 0 } = req.query;
  try {
    let sql = `SELECT * FROM khachhang WHERE 1=1`;
    const params = [];
    if (pageId) { sql += ` AND pageid = ?`; params.push(pageId); }
    if (search) {
      sql += ` AND (fbname LIKE ? OR phone LIKE ? OR userid LIKE ?)`;
      params.push(`%${search}%`, `%${search}%`, `%${search}%`);
    }
    sql += ` ORDER BY joindate DESC LIMIT ? OFFSET ?`;
    params.push(parseInt(limit), parseInt(offset));
    const [rows] = await db.query(sql, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/customers/:id
router.get('/customers/:id', async (req, res) => {
  try {
    const [[row]] = await db.query(`SELECT * FROM khachhang WHERE id = ?`, [req.params.id]);
    if (!row) return res.status(404).json({ error: 'Không tìm thấy' });
    res.json(row);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/customers/:id
router.put('/customers/:id', async (req, res) => {
  const { phone, diachi, label, note, tag, important } = req.body;
  try {
    await db.query(
      `UPDATE khachhang SET phone=?, diachi=?, label=?, note=?, tag=?, important=? WHERE id=?`,
      [phone, diachi, label, note, tag, important, req.params.id]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── PAGES ───────────────────────────────────────────────────

// GET /api/pages
router.get('/pages', async (req, res) => {
  try {
    const [rows] = await db.query(`SELECT id, pageid, name FROM pageinfo`);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
