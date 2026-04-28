require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 5050;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

app.use(cors());
app.use(express.json());

pool.connect((err, client, release) => {
  if (err) {
    console.error('[db] PostgreSQL НЕ подключён:', err.message);
  } else {
    console.log('[db] PostgreSQL подключён');
    release();
  }
});

// Регистрация
app.post('/api/mobile/auth/register', async (req, res) => {
  console.log('📥 Регистрация:', req.body);
  const { name, email, phone, password } = req.body;
  if (!name || !email || !phone || !password) {
    return res.status(400).json({ error: 'Не все поля заполнены' });
  }
  try {
    const existing = await pool.query('SELECT id_пользователя FROM "Пользователи" WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Пользователь уже существует' });
    }
    const result = await pool.query(
      `INSERT INTO "Пользователи" (email, "Пароль", "Имя", "Фамилия", "Отчество", "Телефон") 
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id_пользователя`,
      [email, password, name, '', '', phone]
    );
    const userId = result.rows[0].id_пользователя;
    await pool.query('INSERT INTO "Ученики" (id_пользователя, "Баланс_абонемента") VALUES ($1, $2)', [userId, 0]);
    res.status(201).json({ message: 'Регистрация успешна', userId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// Вход
app.post('/api/mobile/auth/login', async (req, res) => {
  console.log('📥 Вход:', req.body);
  const { phone, password } = req.body;
  if (!phone || !password) {
    return res.status(400).json({ error: 'Телефон и пароль обязательны' });
  }
  try {
    const result = await pool.query(
      'SELECT id_пользователя, "Имя", "Телефон", email, "Пароль" FROM "Пользователи" WHERE "Телефон" = $1',
      [phone]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    const user = result.rows[0];
    if (user.Пароль !== password) {
      return res.status(401).json({ error: 'Неверный пароль' });
    }
    const firstName = user.Имя ?? '';
    const userEmail = user.email != null ? String(user.email) : '';
    res.status(200).json({
      message: 'Вход успешен',
      userId: user.id_пользователя,
      name: firstName,
      firstName,
      phone: user.Телефон ?? '',
      email: userEmail,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// Mock: создание checkout (без реальной оплаты)
app.post('/api/mobile/payment/create-checkout', async (req, res) => {
  console.log('📥 Создание checkout:', req.body);
  res.status(200).json({
    checkoutUrl: 'https://mock.stripe.com/checkout',
    sessionId: 'mock_' + Date.now(),
    mock: true
  });
});

app.post('/api/auth/login', async (req, res) => {
  console.log(req.body)
  const { username, password } = req.body;
  console.log('Login attempt:', username, password); // временный лог

  // Заглушка для тренера
  if (password === 'trainer123') {
    console.log('Trainer login success');
    return res.json({ role: 'trainer', token: 'fake-token' });
  }

  // Администратор
  if (username === '' && password === 'admin123') {
    console.log('Admin login success');
    return res.json({ role: 'admin', token: 'fake-token' });
  }

  // Если ничего не подошло
  console.log('Invalid credentials');
  res.status(401).json({ error: 'invalid_credentials' });
});

// Mock: статус оплаты (всегда успешно)
app.get('/api/mobile/payment/status', async (req, res) => {
  console.log('📥 Статус оплаты, sessionId:', req.query.sessionId);
  res.status(200).json({ paid: true });
});

// Покупка абонемента (возвращает subscription)
app.post('/api/mobile/subscription/purchase', async (req, res) => {
  console.log('📥 Покупка абонемента:', req.body);
  const { planTitle, classesCount, validDays } = req.body;
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + validDays);
  res.status(200).json({
    subscription: {
      title: planTitle,
      totalClasses: classesCount,
      remainingClasses: classesCount,
      expiresAt: expiresAt.toISOString()
    }
  });
});

// Заглушка для расписания (опционально)
app.get('/api/schedule', async (req, res) => {
  res.json([]);
});

app.listen(port, () => {
  console.log(`API сервер запущен на http://localhost:${port}`);
});