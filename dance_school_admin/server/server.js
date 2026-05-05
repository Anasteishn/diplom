/**
 * API: синхронизация с Flutter (X-Sync-Token) + веб-панель (JWT: admin | trainer).
 */
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const nodemailer = require('nodemailer');
const { Pool } = require('pg');
const Stripe = require('stripe');

/**
 * Подхватываем .env из папки проекта, чтобы не задавать DATABASE_URL вручную в каждой сессии cmd.
 * Не перезаписывает уже заданные в среде переменные.
 */
function loadLocalEnv() {
  const candidates = [
    path.join(__dirname, '..', '.env'),
    path.join(__dirname, '.env'),
  ];
  for (const envPath of candidates) {
    try {
      if (!fs.existsSync(envPath)) continue;
      const raw = fs.readFileSync(envPath, 'utf8');
      for (let line of raw.split(/\r?\n/)) {
        line = line.trim();
        if (!line || line.startsWith('#')) continue;
        const eq = line.indexOf('=');
        if (eq <= 0) continue;
        const key = line.slice(0, eq).trim();
        let val = line.slice(eq + 1).trim();
        if (
          (val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))
        ) {
          val = val.slice(1, -1);
        }
        if (!key) continue;
        const cur = process.env[key];
        if (cur === undefined || cur === '') {
          process.env[key] = val;
        }
      }
      console.log(`[env] загружен файл: ${envPath}`);
      return;
    } catch (e) {
      console.warn('[env] не удалось прочитать .env:', e.message);
    }
  }
}
loadLocalEnv();

const PORT = process.env.PORT || 5050;
const DATA_PATH = path.join(__dirname, 'data.json');
const JWT_SECRET = process.env.JWT_SECRET || 'jersey-besy-dev-secret-change-in-production';
const MOBILE_SYNC_TOKEN = process.env.MOBILE_SYNC_TOKEN || 'dev-sync-token';
const DATABASE_URL = process.env.DATABASE_URL || '';
const DB_SCHEMA = process.env.DB_SCHEMA || 'public';
const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = Number(process.env.SMTP_PORT || 587);
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || SMTP_USER || 'no-reply@jersey-besy.local';
/** Пустой ключ или STRIPE_DISABLED=1 — покупка абонемента без Stripe (только запись в БД). */
const STRIPE_DISABLED =
  String(process.env.STRIPE_DISABLED || '')
    .trim()
    .toLowerCase() === '1' ||
  String(process.env.STRIPE_DISABLED || '')
    .trim()
    .toLowerCase() === 'true';
const STRIPE_SECRET_KEY = (process.env.STRIPE_SECRET_KEY || '').trim();
const STRIPE_SUCCESS_URL =
  process.env.STRIPE_SUCCESS_URL || 'http://localhost:3000/?payment=success';
const STRIPE_CANCEL_URL =
  process.env.STRIPE_CANCEL_URL || 'http://localhost:3000/?payment=cancel';

/** Логины тренеров (совпадают с порядком в data.json → trainers) */
const TRAINER_SEED_LOGINS = [
  'nasti',
  'sonya',
  'vika',
  'anna',
  'akhmed',
  'polina_n',
  'kirill',
  'dasha',
  'danil',
  'polina_f',
];

const app = express();
app.use(cors());
app.use(express.json({ limit: '4mb' }));

let pool = null;
let pgEnabled = false;
const reminderTimers = new Map();
const stripe =
  !STRIPE_DISABLED && STRIPE_SECRET_KEY ? new Stripe(STRIPE_SECRET_KEY) : null;

/**
 * В реальных БД часто встречается смешанный регистр колонок из-за кавычек в DDL
 * (например, "Фамилия" vs фамилия). Чтобы не ловить 42703, подбираем фактические
 * имена колонок по information_schema при старте сервера.
 */
const dbColumnNames = {
  users: null,
  students: null,
  subscriptions: null,
  payments: null,
  bookings: null,
  statusPayment: null,
  statusSubscription: null,
};

async function getColumnNameMap(tableName) {
  const tryFetch = async (name) => {
    const r = await pool.query(
      `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = $2
      `,
      [DB_SCHEMA, name]
    );
    return r.rows.map((x) => x.column_name);
  };

  let cols = [];
  try {
    cols = await tryFetch(tableName);
    if (!cols.length) cols = await tryFetch(String(tableName).toLowerCase());
  } catch (e) {
    console.error('[db] Не удалось прочитать информацию о колонках:', e.message);
    cols = [];
  }
  const map = new Map();
  for (const c of cols) map.set(String(c).toLowerCase(), c);
  return map;
}

function pickColumn(colMap, variants) {
  for (const v of variants) {
    const actual = colMap.get(String(v).toLowerCase());
    if (actual) return actual;
  }
  return null;
}

/** TIME в PostgreSQL надёжнее передавать как HH:MM:SS */
function normalizePgTime(t) {
  const s = String(t || '').trim();
  if (!s) return '12:00:00';
  const m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) return s;
  const hh = m[1].padStart(2, '0');
  const mm = m[2];
  const ss = m[3] != null ? m[3] : '00';
  return `${hh}:${mm}:${ss}`;
}

/** Любой существующий ключ расписания — если в «Записи» NOT NULL на ID_расписания */
async function getAnyScheduleRowId() {
  if (!pool) return null;
  const m = await getColumnNameMap('Расписание');
  const idCol = pickColumn(m, ['id_расписания', 'ID_расписания', 'id', 'ID']);
  if (!idCol) return null;
  try {
    const r = await pool.query(`SELECT "${idCol}" AS sid FROM "Расписание" LIMIT 1`);
    return r.rows[0]?.sid ?? null;
  } catch (e) {
    console.warn('[db] не удалось прочитать "Расписание":', e.message);
    return null;
  }
}

async function getAnyDirectionId() {
  if (!pool) return null;
  const m = await getColumnNameMap('Направления');
  const idCol = pickColumn(m, ['id_направления', 'ID_направления', 'id', 'ID']);
  if (!idCol) return null;
  try {
    const r = await pool.query(`SELECT "${idCol}" AS d FROM "Направления" LIMIT 1`);
    return r.rows[0]?.d ?? null;
  } catch (e) {
    return null;
  }
}

/**
 * Если «Расписание» пуста, INSERT одной строки с типовыми колонками (дипломный режим).
 * Без этого FK из «Записи» на ID расписания не из чего взять.
 *
 * Частая схема: только «Время_начала» и «Время_окончания» как NOT NULL timestamp
 * (отдельной колонки «дата» нет — см. типичный DDL курсовых).
 */
async function ensureScheduleSeedIfEmpty() {
  if (!pool) return;
  let n = 0;
  try {
    const c = await pool.query('SELECT COUNT(*)::int AS n FROM "Расписание"');
    n = c.rows[0]?.n ?? 0;
  } catch (e) {
    return;
  }
  if (n > 0) return;

  const R = await getColumnNameMap('Расписание');
  if (R.size === 0) return;

  const startTs = pickColumn(R, ['время_начала', 'Время_начала']);
  const endTs = pickColumn(R, [
    'время_окончания',
    'Время_окончания',
    'время_окончан',
    'Время_окончан',
  ]);
  const idZan = pickColumn(R, ['id_занятия', 'ID_занятия']);
  const mesto = pickColumn(R, ['место', 'Место']);

  /** Схема: два timestamp подряд (как в вашем скриншоте pgAdmin) */
  if (startTs && endTs) {
    try {
      const extraCols = [];
      const extraVals = [];
      const params = [];
      let p = 1;
      if (mesto) {
        extraCols.push(`"${mesto}"`);
        extraVals.push(`$${p++}`);
        params.push('Студия');
      }
      if (idZan) {
        const zid = await getAnyLessonId();
        if (zid != null) {
          extraCols.push(`"${idZan}"`);
          extraVals.push(`$${p++}`);
          params.push(zid);
        }
      }
      const base = `
        INSERT INTO "Расписание" ("${startTs}", "${endTs}"${extraCols.length ? `, ${extraCols.join(', ')}` : ''})
        VALUES (
          (CURRENT_DATE + time '12:00')::timestamp,
          (CURRENT_DATE + time '13:00')::timestamp
          ${extraVals.length ? `, ${extraVals.join(', ')}` : ''}
        )
      `;
      await pool.query(base, params);
      console.log('[db] В «Расписание» добавлена строка по умолчанию (таблица была пуста).');
      return;
    } catch (e) {
      console.warn('[db] Авто-вставка «Расписание» (вариант timestamp):', e.message);
      return;
    }
  }

  const dateCol = pickColumn(R, ['дата_занятия', 'Дата_занятия', 'дата', 'Дата']);
  const timeCol = pickColumn(R, ['время_начала', 'Время_начала', 'время', 'Время']);
  const titleCol = pickColumn(R, ['название', 'Название']);
  const idDirCol = pickColumn(R, [
    'id_направления',
    'ID_направления',
    'id_направление',
    'ID_направление',
  ]);

  const colNames = [];
  const valExprs = [];
  const params = [];
  let pn = 1;

  if (dateCol) {
    colNames.push(`"${dateCol}"`);
    valExprs.push('CURRENT_DATE');
  }
  if (timeCol) {
    colNames.push(`"${timeCol}"`);
    valExprs.push(`'12:00:00'::time`);
  }
  if (titleCol) {
    colNames.push(`"${titleCol}"`);
    valExprs.push(`$${pn++}`);
    params.push('Занятие (авто)');
  }
  if (idDirCol) {
    const dirId = await getAnyDirectionId();
    if (dirId != null) {
      colNames.push(`"${idDirCol}"`);
      valExprs.push(`$${pn++}`);
      params.push(dirId);
    }
  }

  if (colNames.length === 0) {
    console.warn(
      '[db] «Расписание» пуста: не найдены колонки для авто-вставки. Добавьте строку вручную.'
    );
    return;
  }

  try {
    await pool.query(
      `INSERT INTO "Расписание" (${colNames.join(', ')}) VALUES (${valExprs.join(', ')})`,
      params
    );
    console.log('[db] В «Расписание» добавлена строка по умолчанию (таблица была пуста).');
  } catch (e) {
    console.warn('[db] Авто-заполнение «Расписание» не удалось:', e.message);
  }
}

async function getAnyLessonId() {
  if (!pool) return null;
  const m = await getColumnNameMap('Занятия');
  if (m.size === 0) return null;
  const idCol = pickColumn(m, ['id_занятия', 'ID_занятия', 'id', 'ID']);
  if (!idCol) return null;
  try {
    const r = await pool.query(`SELECT "${idCol}" AS z FROM "Занятия" LIMIT 1`);
    return r.rows[0]?.z ?? null;
  } catch (e) {
    return null;
  }
}

async function initDbColumnNames() {
  if (!pgEnabled || !pool) return;
  const usersCols = await getColumnNameMap('Пользователи');
  const studentsCols = await getColumnNameMap('Ученики');

  dbColumnNames.users = {
    id: pickColumn(usersCols, ['id_пользователя', 'ID_пользователя']),
    lastName: pickColumn(usersCols, ['фамилия', 'Фамилия']),
    firstName: pickColumn(usersCols, ['имя', 'Имя']),
    middleName: pickColumn(usersCols, ['отчество', 'Отчество']),
    email: pickColumn(usersCols, ['email', 'Email', 'e-mail', 'E-mail']),
    phone: pickColumn(usersCols, ['телефон', 'Телефон', 'phone', 'Phone']),
    password: pickColumn(usersCols, ['пароль', 'Пароль', 'password', 'Password']),
    role: pickColumn(usersCols, ['роль', 'Роль', 'role', 'Role']),
  };

  dbColumnNames.students = {
    id: pickColumn(studentsCols, ['id_ученика', 'ID_ученика']),
    userId: pickColumn(studentsCols, ['id_пользователя', 'ID_пользователя']),
    balance: pickColumn(studentsCols, ['баланс_абонемента', 'Баланс_абонемента']),
    newsletter: pickColumn(studentsCols, ['согласие_на_рассылку', 'Согласие_на_рассылку']),
  };

  const subCols = await getColumnNameMap('Абонементы');
  const payCols = await getColumnNameMap('Платежи');
  dbColumnNames.subscriptions = {
    id: pickColumn(subCols, ['id_абонемента', 'ID_абонемента']),
    studentId: pickColumn(subCols, ['id_ученика', 'ID_ученика']),
    statusId: pickColumn(subCols, ['id_статуса', 'ID_статуса']),
    title: pickColumn(subCols, ['название', 'Название']),
    price: pickColumn(subCols, ['цена', 'Цена']),
    classesTotal: pickColumn(subCols, ['кол_во_занятий', 'Кол_во_занятий']),
    classesUsed: pickColumn(subCols, ['использовано_занятий', 'Использовано_занятий']),
    purchaseDate: pickColumn(subCols, ['дата_покупки', 'Дата_покупки']),
    expires: pickColumn(subCols, ['срок_действия', 'Срок_действия']),
  };
  dbColumnNames.payments = {
    studentId: pickColumn(payCols, ['id_ученика', 'ID_ученика']),
    subscriptionId: pickColumn(payCols, ['id_абонемента', 'ID_абонемента']),
    paymentStatusId: pickColumn(payCols, [
      'id_статуса_платежа',
      'ID_статуса_платежа',
      'id_статуса',
      'ID_статуса',
    ]),
    amount: pickColumn(payCols, ['сумма', 'Сумма']),
    method: pickColumn(payCols, ['способ_оплаты', 'Способ_оплаты']),
  };

  const bookingCols = await getColumnNameMap('Записи');
  const stPayCols = await getColumnNameMap('Статус_платежа');
  const stSubCols = await getColumnNameMap('Статус_абонемента');
  dbColumnNames.bookings = {
    id: pickColumn(bookingCols, ['id_записи', 'ID_записи']),
    studentId: pickColumn(bookingCols, ['id_ученика', 'ID_ученика']),
    /** Часто NOT NULL в учебных БД — без неё INSERT в «Записи» падает. */
    scheduleId: pickColumn(bookingCols, [
      'id_расписания',
      'ID_расписания',
      'id_расписание',
      'ID_расписание',
    ]),
    classTitle: pickColumn(bookingCols, ['название_занятия', 'Название_занятия']),
    trainerName: pickColumn(bookingCols, ['имя_тренера', 'Имя_тренера']),
    classDate: pickColumn(bookingCols, ['дата_занятия', 'Дата_занятия']),
    startTime: pickColumn(bookingCols, ['время_начала', 'Время_начала']),
    endTime: pickColumn(bookingCols, ['время_окончания', 'Время_окончания']),
    duration: pickColumn(bookingCols, ['длительность_минут', 'Длительность_минут']),
    usedSub: pickColumn(bookingCols, ['использован_абонемент', 'Использован_абонемент']),
    status: pickColumn(bookingCols, ['статус_записи', 'Статус_записи']),
  };
  dbColumnNames.statusPayment = {
    id: pickColumn(stPayCols, ['id_статуса', 'ID_статуса']),
    name: pickColumn(stPayCols, ['название_статуса', 'Название_статуса']),
  };
  dbColumnNames.statusSubscription = {
    id: pickColumn(stSubCols, ['id_статуса', 'ID_статуса']),
    name: pickColumn(stSubCols, ['название_статуса', 'Название_статуса']),
  };

  // Минимальная проверка: без этих полей auth/registration работать не сможет.
  const requiredUsers = ['id', 'firstName', 'email', 'phone', 'password', 'role'];
  const missingUsers = requiredUsers.filter((k) => !dbColumnNames.users[k]);
  const requiredStudents = ['id', 'userId'];
  const missingStudents = requiredStudents.filter((k) => !dbColumnNames.students[k]);

  if (missingUsers.length || missingStudents.length) {
    console.warn(
      '[db] Предупреждение: не найдены колонки:',
      { users: missingUsers, students: missingStudents }
    );
  }
}

function createMailer() {
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS) return null;
  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,
    auth: {
      user: SMTP_USER,
      pass: SMTP_PASS,
    },
  });
}

const mailer = createMailer();

async function sendEmail({ to, subject, text }) {
  if (!to) return;
  if (!mailer) {
    console.log(`[mail:stub] ${to} | ${subject} | ${text}`);
    return;
  }
  await mailer.sendMail({
    from: SMTP_FROM,
    to,
    subject,
    text,
  });
}

function readData() {
  const raw = fs.readFileSync(DATA_PATH, 'utf8');
  return JSON.parse(raw);
}

async function initPostgres() {
  if (!DATABASE_URL) {
    console.log(
      '[db] DATABASE_URL не задан — мобильный вход/абонементы недоступны. Создайте файл dance_school_admin/.env с DATABASE_URL=... или задайте переменную окружения.'
    );
    console.log('[db] Чаты и админ через data.json при этом могут работать.');
    return;
  }
  try {
    pool = new Pool({
      connectionString: DATABASE_URL,
      ssl:
        DATABASE_URL.includes('localhost') || DATABASE_URL.includes('127.0.0.1')
          ? false
          : { rejectUnauthorized: false },
    });
    pool.on('connect', (client) => {
      client
        .query(`SET search_path TO "${DB_SCHEMA}", public`)
        .catch((e) => console.error('[db] Не удалось установить search_path:', e.message));
    });
    // Инициализируем search_path для первого подключения.
    await pool.query(`SET search_path TO "${DB_SCHEMA}", public`);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS chat_messages (
        id BIGSERIAL PRIMARY KEY,
        trainer_name TEXT NOT NULL,
        author TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    await pool.query(`
      ALTER TABLE "Ученики"
      ADD COLUMN IF NOT EXISTS "согласие_на_рассылку" BOOLEAN DEFAULT FALSE;
    `).catch(() => {});
    await pool.query(`
      ALTER TABLE "Записи"
      ADD COLUMN IF NOT EXISTS "название_занятия" TEXT;
    `).catch(() => {});
    await pool.query(`
      ALTER TABLE "Записи"
      ADD COLUMN IF NOT EXISTS "имя_тренера" TEXT;
    `).catch(() => {});
    await pool.query(`
      ALTER TABLE "Записи"
      ADD COLUMN IF NOT EXISTS "id_stripe_session" TEXT;
    `).catch(() => {});
    pgEnabled = true;
    console.log(
      `[db] PostgreSQL подключен (schema=${DB_SCHEMA}), чаты сохраняются в БД`
    );
    await initDbColumnNames();
    // await ensureScheduleSeedIfEmpty();
  } catch (e) {
    console.error('[db] Ошибка подключения к PostgreSQL, используем data.json:', e.message);
    pgEnabled = false;
  }
}

function verifyStudentJwt(req) {
  const v = verifyJwt(req);
  if (!v.ok) return v;
  if (v.payload.role !== 'student') return { ok: false, error: 'student_only' };
  return v;
}

async function getStudentByUserId(userId) {
  if (!dbColumnNames.students?.id || !dbColumnNames.students?.userId) {
    await initDbColumnNames();
  }
  const s = dbColumnNames.students;
  const r = await pool.query(
    `
      SELECT "${s.id}" AS student_id
      FROM "Ученики"
      WHERE "${s.userId}" = $1
      LIMIT 1
    `,
    [userId]
  );
  return r.rows[0] || null;
}

async function getOrCreatePaymentStatusId(statusName) {
  if (!dbColumnNames.statusPayment?.id || !dbColumnNames.statusPayment?.name) {
    await initDbColumnNames();
  }
  const sp = dbColumnNames.statusPayment;
  if (!sp.id || !sp.name) {
    throw new Error('Таблица "Статус_платежа": не найдены колонки статуса');
  }
  const found = await pool.query(
    `
      SELECT "${sp.id}" AS id FROM "Статус_платежа"
      WHERE LOWER("${sp.name}"::text) = LOWER($1)
      LIMIT 1
    `,
    [statusName]
  );
  if (found.rows[0]) return found.rows[0].id;
  const ins = await pool.query(
    `
      INSERT INTO "Статус_платежа" ("${sp.name}")
      VALUES ($1)
      RETURNING "${sp.id}" AS id
    `,
    [statusName]
  );
  return ins.rows[0].id;
}

async function getOrCreateSubscriptionStatusId(statusName) {
  if (!dbColumnNames.statusSubscription?.id || !dbColumnNames.statusSubscription?.name) {
    await initDbColumnNames();
  }
  const ss = dbColumnNames.statusSubscription;
  if (!ss.id || !ss.name) {
    throw new Error('Таблица "Статус_абонемента": не найдены колонки статуса');
  }
  const found = await pool.query(
    `
      SELECT "${ss.id}" AS id FROM "Статус_абонемента"
      WHERE LOWER("${ss.name}"::text) = LOWER($1)
      LIMIT 1
    `,
    [statusName]
  );
  if (found.rows[0]) return found.rows[0].id;
  const ins = await pool.query(
    `
      INSERT INTO "Статус_абонемента" ("${ss.name}")
      VALUES ($1)
      RETURNING "${ss.id}" AS id
    `,
    [statusName]
  );
  return ins.rows[0].id;
}

async function getDialogsMapFromDb() {
  if (!pgEnabled || !pool) return null;
  const result = await pool.query(
    `
      SELECT trainer_name, author, text, created_at
      FROM chat_messages
      ORDER BY created_at ASC, id ASC
    `
  );
  const dialogs = {};
  for (const row of result.rows) {
    if (!dialogs[row.trainer_name]) dialogs[row.trainer_name] = [];
    dialogs[row.trainer_name].push({
      author: row.author,
      text: row.text,
      createdAt: new Date(row.created_at).toISOString(),
    });
  }
  return dialogs;
}

async function saveChatMessage({ trainerName, author, text }) {
  const safeText = String(text || '').trim();
  if (!safeText) return false;

  if (pgEnabled && pool) {
    await pool.query(
      `
      INSERT INTO chat_messages (trainer_name, author, text)
      VALUES ($1, $2, $3)
    `,
      [trainerName, author, safeText]
    );
    return true;
  }

  // fallback: старое хранение в JSON
  const data = readData();
  ensureAccounts(data);
  if (!data.dialogs) data.dialogs = {};
  if (!data.dialogs[trainerName]) data.dialogs[trainerName] = [];
  data.dialogs[trainerName].push({
    author,
    text: safeText,
    createdAt: new Date().toISOString(),
  });
  writeData(data);
  return true;
}

async function buildStudioWithDialogs(data) {
  const fromDb = await getDialogsMapFromDb();
  if (fromDb) {
    return { ...data, dialogs: fromDb };
  }
  return data;
}

function writeData(obj) {
  fs.writeFileSync(DATA_PATH, JSON.stringify(obj, null, 2), 'utf8');
}

function stripAccounts(data) {
  const { accounts: _a, ...rest } = data;
  return rest;
}

function ensureAccounts(data) {
  if (Array.isArray(data.accounts) && data.accounts.length > 0) return data;

  const hash = (p) => bcrypt.hashSync(p, 10);
  const trainers = data.trainers || [];
  const trainerAccounts = trainers.map((t, i) => ({
    login: TRAINER_SEED_LOGINS[i] || `trainer_${i + 1}`,
    passwordHash: hash('trainer123'),
    role: 'trainer',
    trainerName: t.name,
  }));

  data.accounts = [
    { login: 'admin', passwordHash: hash('admin123'), role: 'admin' },
    ...trainerAccounts,
  ];
  writeData(data);
  console.log(
    '[auth] Созданы учётные записи: admin / admin123; тренеры — см. README (пароль trainer123)'
  );
  return data;
}

function verifySync(req) {
  const t = req.headers['x-sync-token'];
  return t && t === MOBILE_SYNC_TOKEN;
}

function parseBearer(req) {
  const h = req.headers.authorization;
  if (!h || !h.startsWith('Bearer ')) return null;
  return h.slice(7).trim();
}

function verifyJwt(req) {
  const token = parseBearer(req);
  if (!token) return { ok: false, error: 'no_token' };
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    return { ok: true, payload };
  } catch {
    return { ok: false, error: 'invalid_token' };
  }
}

function filterForTrainer(data, trainerName) {
  const bookings = (data.bookings || []).filter((b) => b.trainerName === trainerName);
  const dialogs = {};
  const thread = (data.dialogs && data.dialogs[trainerName]) || [];
  dialogs[trainerName] = thread;
  return {
    role: 'trainer',
    trainerName,
    bookings,
    dialogs,
  };
}

function mergeStudioPayload(incoming, current) {
  return {
    trainers: incoming.trainers != null ? incoming.trainers : current.trainers,
    classTemplates:
      incoming.classTemplates != null ? incoming.classTemplates : current.classTemplates,
    bookings: incoming.bookings != null ? incoming.bookings : current.bookings,
    // При PostgreSQL-режиме чат хранится в БД; в JSON-режиме оставляем старое поведение.
    dialogs: pgEnabled
      ? current.dialogs
      : incoming.dialogs != null
      ? incoming.dialogs
      : current.dialogs,
    accounts: current.accounts || [],
  };
}

// ——— routes ———

app.post('/api/auth/login', (req, res) => {
  try {
    const { login, password } = req.body || {};
    console.log('Login attempt:', { login, password });
    if (!password) {
      return res.status(400).json({ error: 'password_required' });
    }
    let data = readData();
    data = ensureAccounts(data);

    let user = null;
    // Если логин отсутствует или пустая строка — ищем администратора
    if (!login || String(login).trim() === '') {
      user = (data.accounts || []).find(a => a.role === 'admin');
      console.log('Looking for admin, found:', !!user);
    } else {
      const loginLower = String(login).trim().toLowerCase();
      user = (data.accounts || []).find(
        a => a.login && a.login.toLowerCase() === loginLower
      );
      console.log('Looking for login:', loginLower, 'found:', !!user);
    }

    if (!user) {
      console.log('User not found');
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const isPasswordValid = bcrypt.compareSync(String(password), user.passwordHash);
    console.log('Password valid:', isPasswordValid);
    if (!isPasswordValid) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const tokenPayload = {
      role: user.role,
      login: user.login,
      trainerName: user.trainerName || null,
    };
    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: '7d' });
    return res.json({
      token,
      role: user.role,
      login: user.login,
      trainerName: user.trainerName || null,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'login_failed' });
  }
});

/* app.post('/api/mobile/auth/register', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.users || !dbColumnNames.students) {
      await initDbColumnNames();
    }
    const {
      lastName = '',
      firstName = '',
      middleName = '',
      email = '',
      phone = '',
      password = '',
      newsletterConsent = false,
    } = req.body || {};

    if (!firstName || !email || !phone || !password) {
      return res.status(400).json({ error: 'required_fields' });
    }
    const passHash = bcrypt.hashSync(String(password), 10);
    const u = dbColumnNames.users || {};
    const s = dbColumnNames.students || {};
    if (!u.id || !u.firstName || !u.email || !u.phone || !u.password || !u.role) {
      return res.status(500).json({
        error: 'schema_mismatch_users',
        message: 'Не найдены обязательные колонки в таблице "Пользователи".',
      });
    }
    if (!s.id || !s.userId) {
      return res.status(500).json({
        error: 'schema_mismatch_students',
        message: 'Не найдены обязательные колонки в таблице "Ученики".',
      });
    }

    const usersCols = [];
    const usersVals = [];
    if (u.lastName) {
      usersCols.push(u.lastName);
      usersVals.push(lastName || null);
    }
    if (u.firstName) {
      usersCols.push(u.firstName);
      usersVals.push(firstName);
    }
    if (u.middleName) {
      usersCols.push(u.middleName);
      usersVals.push(middleName || null);
    }
    if (u.email) {
      usersCols.push(u.email);
      usersVals.push(email);
    }
    if (u.phone) {
      usersCols.push(u.phone);
      usersVals.push(phone);
    }
    if (u.password) {
      usersCols.push(u.password);
      usersVals.push(passHash);
    }
    if (u.role) {
      usersCols.push(u.role);
      usersVals.push('ученик');
    }

    const insertedUser = await pool.query(
      `
      INSERT INTO "Пользователи" (
        ${usersCols.map((c) => `"${c}"`).join(', ')}
      )
      VALUES (${usersCols.map((_, i) => `$${i + 1}`).join(', ')})
      RETURNING "${u.id}" AS user_id
      `,
      usersVals
    );
    const userId = insertedUser.rows[0].user_id;

    const studentCols = [];
    const studentVals = [];
    if (s.userId) {
      studentCols.push(s.userId);
      studentVals.push(userId);
    }
    if (s.balance) {
      studentCols.push(s.balance);
      studentVals.push(0);
    }
    if (s.newsletter) {
      studentCols.push(s.newsletter);
      studentVals.push(Boolean(newsletterConsent));
    }
    const insertedStudent = await pool.query(
      `
      INSERT INTO "Ученики" (${studentCols.map((c) => `"${c}"`).join(', ')})
      VALUES (${studentCols.map((_, i) => `$${i + 1}`).join(', ')})
      RETURNING "${s.id}" AS student_id
      `,
      studentVals
    );
    const studentId = insertedStudent.rows[0].student_id;

    await sendEmail({
      to: email,
      subject: 'Регистрация в Jersey BESY',
      text: `Здравствуйте, ${firstName}! Вы успешно зарегистрированы.`,
    });
    return res.json({ ok: true, userId, studentId });
  } catch (e) {
    if (String(e.message || '').includes('unique') || String(e.code || '') === '23505') {
      return res.status(409).json({ error: 'user_exists' });
    }
    if (String(e.code || '') === '42P01') {
      return res.status(500).json({
        error: 'schema_not_initialized',
        message: `Таблицы не найдены в схеме "${DB_SCHEMA}"`,
      });
    }
    console.error(e);
    return res.status(500).json({ error: 'register_failed' });
  }
}); */

/* app.post('/api/mobile/auth/login', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.users || !dbColumnNames.students) {
      await initDbColumnNames();
    }
    const { phone = '', password = '' } = req.body || {};
    if (!phone || !password) return res.status(400).json({ error: 'required_fields' });

    const uCols = dbColumnNames.users || {};
    const sCols = dbColumnNames.students || {};
    if (!uCols.id || !uCols.firstName || !uCols.email || !uCols.phone || !uCols.password || !uCols.role) {
      return res.status(500).json({
        error: 'schema_mismatch_users',
        message: 'Не найдены обязательные колонки в таблице "Пользователи".',
      });
    }
    if (!sCols.id || !sCols.userId) {
      return res.status(500).json({
        error: 'schema_mismatch_students',
        message: 'Не найдены обязательные колонки в таблице "Ученики".',
      });
    }

    const userQ = await pool.query(
      `
      SELECT
        p."${uCols.id}" AS user_id,
        p."${uCols.firstName}" AS first_name,
        p."${uCols.email}" AS email,
        p."${uCols.phone}" AS phone,
        p."${uCols.password}" AS pass_hash,
        p."${uCols.role}" AS role_name,
        u."${sCols.id}" AS student_id,
        ${sCols.newsletter ? `COALESCE(u."${sCols.newsletter}", FALSE)` : 'FALSE'} AS newsletter
      FROM "Пользователи" p
      JOIN "Ученики" u ON u."${sCols.userId}" = p."${uCols.id}"
      WHERE p."${uCols.phone}" = $1
      LIMIT 1
      `,
      [phone]
    );
    const u = userQ.rows[0];
    if (!u || u.role_name !== 'ученик') {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    if (!bcrypt.compareSync(String(password), u.pass_hash)) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    const token = jwt.sign(
      {
        role: 'student',
        userId: u.user_id,
        studentId: u.student_id,
      },
      JWT_SECRET,
      { expiresIn: '14d' }
    );
    return res.json({
      token,
      userId: u.user_id,
      studentId: u.student_id,
      firstName: u.first_name || 'Ученик',
      phone: u.phone || '',
      email: u.email || '',
      newsletterConsent: Boolean(u.newsletter),
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'login_failed' });
  }
}); */

app.get('/api/mobile/bookings', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.bookings?.id) await initDbColumnNames();
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    const studentId = Number(v.payload.studentId);
    if (!Number.isFinite(studentId)) {
      return res.status(401).json({ error: 'invalid_token' });
    }
    const B = dbColumnNames.bookings;
    if (!B.id || !B.studentId || !B.classDate || !B.startTime) {
      return res.status(500).json({ error: 'bookings_schema_mismatch' });
    }
    const titleExpr = B.classTitle
      ? `COALESCE("${B.classTitle}", 'Занятие')`
      : `'Занятие'`;
    const trainerExpr = B.trainerName
      ? `COALESCE("${B.trainerName}", 'Тренер')`
      : `'Тренер'`;
    const durExpr = B.duration ? `COALESCE("${B.duration}", 55)` : '55';
    const statusExpr = B.status
      ? `COALESCE("${B.status}", 'подтверждена')`
      : `'подтверждена'`;
    const rows = await pool.query(
      `
      SELECT
        "${B.id}" AS id,
        ${titleExpr} AS class_name,
        ${trainerExpr} AS trainer_name,
        "${B.classDate}"::text AS class_date,
        "${B.startTime}"::text AS start_time,
        ${durExpr} AS duration,
        ${statusExpr} AS status
      FROM "Записи"
      WHERE "${B.studentId}" = $1
      ORDER BY "${B.classDate}" ASC, "${B.startTime}" ASC
      `,
      [studentId]
    );
    return res.json({
      bookings: rows.rows.map((r) => ({
        id: r.id,
        className: r.class_name,
        trainerName: r.trainer_name,
        date: r.class_date,
        time: String(r.start_time || '').slice(0, 5),
        durationMinutes: Number(r.duration || 55),
        status: r.status,
      })),
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'bookings_failed' });
  }
});

app.post('/api/mobile/bookings', async (req, res) => {
  try {
    let studentId = null;
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.slice(7);
      try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const userId = decoded.userId;
        const studentRes = await pool.query('SELECT id_ученика FROM "Ученики" WHERE id_пользователя = $1', [userId]);
        if (studentRes.rows.length > 0) {
          studentId = studentRes.rows[0].id_ученика;
        }
      } catch (err) {
        console.warn('Token invalid, will use fallback student');
      }
    }

    // Если не удалось получить studentId из токена, используем переданный или первого ученика
    if (!studentId) {
      if (req.body.studentId) {
        studentId = req.body.studentId;
      } else {
        // Найти любого ученика (для демо)
        const anyStudent = await pool.query('SELECT id_ученика FROM "Ученики" LIMIT 1');
        if (anyStudent.rows.length === 0) {
          // Создать тестового ученика
          const user = await pool.query(
            `INSERT INTO "Пользователи" (email, "Пароль", "Имя", "Фамилия", "Телефон", "Роль")
             VALUES ('demo@dance.ru', '123', 'Демо', 'Ученик', '0000000000', 'ученик')
             RETURNING id_пользователя`
          );
          const userId = user.rows[0].id_пользователя;
          const stud = await pool.query(
            `INSERT INTO "Ученики" (id_пользователя, "Баланс_абонемента") VALUES ($1, 5) RETURNING id_ученика`,
            [userId]
          );
          studentId = stud.rows[0].id_ученика;
        } else {
          studentId = anyStudent.rows[0].id_ученика;
        }
      }
    }

    const { className, trainerName, date, time, durationMinutes } = req.body;
    if (!className || !date || !time) {
      return res.status(400).json({ error: 'required_fields' });
    }

    const result = await pool.query(
      `INSERT INTO "Записи" (id_ученика, "Дата_занятия", "Время_начала", "Длительность_минут", "Статус_записи", "название_занятия", "имя_тренера")
       VALUES ($1, $2, $3, $4, 'подтверждена', $5, $6) RETURNING id_записи`,
      [studentId, date, time, durationMinutes || 55, className, trainerName || 'Тренер']
    );
    res.status(200).json({ ok: true, bookingId: result.rows[0].id_записи });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'booking_failed' });
  }
});

app.post('/api/mobile/bookings/cancel', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.bookings?.id || !dbColumnNames.students?.id) {
      await initDbColumnNames();
    }
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    const studentId = Number(v.payload.studentId);
    if (!Number.isFinite(studentId)) {
      return res.status(401).json({ error: 'invalid_token' });
    }
    const bookingId = Number(req.body?.bookingId || 0);
    if (!bookingId) return res.status(400).json({ error: 'booking_id_required' });

    const B = dbColumnNames.bookings;
    const sb = dbColumnNames.students;
    if (!B.status || !B.id || !B.studentId || !B.classDate || !B.startTime || !sb.balance) {
      return res.status(500).json({ error: 'bookings_schema_mismatch' });
    }
    const returningClassName = B.classTitle
      ? `"${B.classTitle}" AS class_name`
      : `'—' AS class_name`;
    const up = await pool.query(
      `
      UPDATE "Записи"
      SET "${B.status}" = 'отменена'
      WHERE "${B.id}" = $1 AND "${B.studentId}" = $2
      RETURNING ${returningClassName}, "${B.classDate}"::text AS class_date, "${B.startTime}"::text AS class_time
      `,
      [bookingId, studentId]
    );
    if (!up.rows[0]) return res.status(404).json({ error: 'booking_not_found' });

    await pool.query(
      `UPDATE "Ученики" SET "${sb.balance}" = "${sb.balance}" + 1 WHERE "${sb.id}" = $1`,
      [studentId]
    );
    return res.json({ ok: true, booking: up.rows[0] });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'booking_cancel_failed' });
  }
});

app.get('/api/mobile/subscription', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.students || !dbColumnNames.subscriptions) {
      await initDbColumnNames();
    }
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    const studentId = Number(v.payload.studentId);
    if (!Number.isFinite(studentId)) {
      return res.status(401).json({ error: 'invalid_token' });
    }

    const sb = dbColumnNames.students;
    const su = dbColumnNames.subscriptions;
    if (!sb?.id || !sb?.balance || !su?.studentId || !su?.title || !su?.classesTotal || !su?.expires) {
      return res.status(500).json({ error: 'subscription_schema_mismatch' });
    }

    const studentQ = await pool.query(
      `SELECT "${sb.balance}" AS balance FROM "Ученики" WHERE "${sb.id}" = $1 LIMIT 1`,
      [studentId]
    );
    const orderParts = [];
    if (su.purchaseDate) orderParts.push(`"${su.purchaseDate}" DESC`);
    if (su.id) orderParts.push(`"${su.id}" DESC`);
    const orderBy = orderParts.length ? orderParts.join(', ') : `"${su.expires}" DESC`;
    const subQ = await pool.query(
      `
      SELECT "${su.title}" AS title, "${su.classesTotal}" AS total, "${su.expires}"::text AS expires_at
      FROM "Абонементы"
      WHERE "${su.studentId}" = $1
      ORDER BY ${orderBy}
      LIMIT 1
      `,
      [studentId]
    );
    const sub = subQ.rows[0] || null;
    if (!sub) return res.json({ subscription: null });
    return res.json({
      subscription: {
        title: sub.title,
        totalClasses: Number(sub.total || 0),
        remainingClasses: Number(studentQ.rows[0]?.balance || 0),
        expiresAt: sub.expires_at,
      },
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'subscription_failed' });
  }
});

app.post('/api/mobile/payment/create-checkout', async (req, res) => {
  try {
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    if (!stripe) {
      return res.json({
        ok: true,
        mock: true,
        checkoutUrl: null,
        sessionId: null,
        message: 'Stripe не настроен — оплата пропускается (режим разработки).',
      });
    }
    const { planTitle = '', amountRub = 0 } = req.body || {};
    if (!planTitle || !amountRub) return res.status(400).json({ error: 'required_fields' });
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      success_url: STRIPE_SUCCESS_URL,
      cancel_url: STRIPE_CANCEL_URL,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: 'rub',
            unit_amount: Number(amountRub) * 100,
            product_data: { name: `Абонемент ${planTitle}` },
          },
        },
      ],
      metadata: {
        studentId: String(v.payload.studentId),
        planTitle: String(planTitle),
      },
    });
    return res.json({ ok: true, checkoutUrl: session.url, sessionId: session.id });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'payment_create_failed' });
  }
});

app.get('/api/mobile/payment/status', async (req, res) => {
  try {
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    if (!stripe) {
      return res.json({ ok: true, paid: false, mock: true });
    }
    const sessionId = String(req.query?.sessionId || '').trim();
    if (!sessionId) return res.status(400).json({ error: 'session_id_required' });
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    return res.json({
      ok: true,
      paid: session.payment_status === 'paid',
      sessionId: session.id,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'payment_status_failed' });
  }
});

app.post('/api/mobile/subscription/purchase', async (req, res) => {
  try {
    if (!pgEnabled || !pool) return res.status(503).json({ error: 'db_unavailable' });
    if (!dbColumnNames.students || !dbColumnNames.subscriptions || !dbColumnNames.payments) {
      await initDbColumnNames();
    }
    const v = verifyStudentJwt(req);
    if (!v.ok) return res.status(401).json({ error: v.error || 'unauthorized' });
    const studentId = Number(v.payload.studentId);
    if (!Number.isFinite(studentId)) {
      return res.status(401).json({ error: 'invalid_token' });
    }
    const {
      planTitle = '',
      classesCount = 0,
      priceRub = 0,
      validDays = 30,
      stripeSessionId = null,
    } = req.body || {};
    if (!planTitle || !classesCount || !priceRub) {
      return res.status(400).json({ error: 'required_fields' });
    }

    /** Оплата: при наличии Stripe доверяем только session в Stripe, не флагу `paid` с клиента. */
    if (stripe) {
      const sid = stripeSessionId ? String(stripeSessionId).trim() : '';
      if (!sid) {
        return res.status(400).json({ error: 'payment_not_confirmed' });
      }
      const sess = await stripe.checkout.sessions.retrieve(sid);
      if (sess.payment_status !== 'paid') {
        return res.status(400).json({ error: 'payment_not_confirmed' });
      }
      const metaStudent = sess.metadata && sess.metadata.studentId;
      if (metaStudent && String(metaStudent) !== String(studentId)) {
        return res.status(400).json({ error: 'payment_session_mismatch' });
      }
    }

    const subStatusId = await getOrCreateSubscriptionStatusId('активен');
    const payStatusId = await getOrCreatePaymentStatusId('успешно');

    const A = dbColumnNames.subscriptions;
    const P = dbColumnNames.payments;
    const sb = dbColumnNames.students;
    const usedCol = A.classesUsed || A.classesTotal;
    if (
      !A?.id ||
      !A?.studentId ||
      !A?.statusId ||
      !A?.title ||
      !A?.price ||
      !A?.classesTotal ||
      !usedCol ||
      !A?.expires ||
      !P?.studentId ||
      !P?.subscriptionId ||
      !P?.paymentStatusId ||
      !P?.amount ||
      !P?.method ||
      !sb?.id ||
      !sb?.balance
    ) {
      return res.status(500).json({ error: 'subscription_schema_mismatch' });
    }

    let subIns;
    if (A.purchaseDate) {
      subIns = await pool.query(
        `
        INSERT INTO "Абонементы" (
          "${A.studentId}", "${A.statusId}", "${A.title}", "${A.price}",
          "${A.classesTotal}", "${usedCol}", "${A.purchaseDate}", "${A.expires}"
        )
        VALUES ($1, $2, $3, $4, $5, $6, CURRENT_DATE, CURRENT_DATE + ($7 || ' day')::interval)
        RETURNING "${A.id}" AS subscription_id, "${A.expires}"::text AS expires_at
        `,
        [studentId, subStatusId, planTitle, priceRub, classesCount, 0, validDays]
      );
    } else {
      subIns = await pool.query(
        `
        INSERT INTO "Абонементы" (
          "${A.studentId}", "${A.statusId}", "${A.title}", "${A.price}",
          "${A.classesTotal}", "${usedCol}", "${A.expires}"
        )
        VALUES ($1, $2, $3, $4, $5, $6, CURRENT_DATE + ($7 || ' day')::interval)
        RETURNING "${A.id}" AS subscription_id, "${A.expires}"::text AS expires_at
        `,
        [studentId, subStatusId, planTitle, priceRub, classesCount, 0, validDays]
      );
    }
    const subId = subIns.rows[0].subscription_id;

    await pool.query(
      `
      INSERT INTO "Платежи" (
        "${P.studentId}", "${P.subscriptionId}", "${P.paymentStatusId}", "${P.amount}", "${P.method}"
      )
      VALUES ($1, $2, $3, $4, $5)
      `,
      [studentId, subId, payStatusId, priceRub, stripeSessionId ? 'stripe' : 'manual']
    );

    await pool.query(
      `UPDATE "Ученики" SET "${sb.balance}" = $2 WHERE "${sb.id}" = $1`,
      [studentId, classesCount]
    );

    return res.json({
      ok: true,
      subscription: {
        title: planTitle,
        totalClasses: Number(classesCount),
        remainingClasses: Number(classesCount),
        expiresAt: subIns.rows[0].expires_at,
      },
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'subscription_purchase_failed' });
  }
});

app.post('/api/notify/registration', async (req, res) => {
  try {
    if (!verifySync(req)) return res.status(403).json({ error: 'sync_only' });
    const email = String(req.body?.email || '').trim();
    const userName = String(req.body?.userName || 'Пользователь').trim();
    if (!email) return res.status(400).json({ error: 'email_required' });
    await sendEmail({
      to: email,
      subject: 'Добро пожаловать в Jersey BESY',
      text: `Здравствуйте, ${userName}! Регистрация прошла успешно.`,
    });
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'notify_failed' });
  }
});

app.post('/api/notify/booking', async (req, res) => {
  try {
    if (!verifySync(req)) return res.status(403).json({ error: 'sync_only' });
    const email = String(req.body?.email || '').trim();
    const className = String(req.body?.className || 'занятие').trim();
    const classDateTime = String(req.body?.classDateTime || '').trim();
    if (!email) return res.status(400).json({ error: 'email_required' });
    await sendEmail({
      to: email,
      subject: 'Успешная запись на занятие',
      text: `Вы успешно записаны на ${className}. Дата и время: ${classDateTime}.`,
    });
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'notify_failed' });
  }
});

app.post('/api/notify/cancel', async (req, res) => {
  try {
    if (!verifySync(req)) return res.status(403).json({ error: 'sync_only' });
    const email = String(req.body?.email || '').trim();
    const className = String(req.body?.className || 'занятие').trim();
    const classDateTime = String(req.body?.classDateTime || '').trim();
    if (!email) return res.status(400).json({ error: 'email_required' });
    await sendEmail({
      to: email,
      subject: 'Отмена записи',
      text: `Запись на ${className} (${classDateTime}) была отменена.`,
    });
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'notify_failed' });
  }
});

app.post('/api/notify/reminder', async (req, res) => {
  try {
    if (!verifySync(req)) return res.status(403).json({ error: 'sync_only' });
    const bookingKey = String(req.body?.bookingKey || '').trim();
    const email = String(req.body?.email || '').trim();
    const className = String(req.body?.className || 'занятие').trim();
    const classDateTime = new Date(req.body?.classDateTime);
    if (!bookingKey || !email || Number.isNaN(classDateTime.getTime())) {
      return res.status(400).json({ error: 'invalid_payload' });
    }

    const remindAt = classDateTime.getTime() - 60 * 60 * 1000;
    const delay = remindAt - Date.now();
    if (reminderTimers.has(bookingKey)) {
      clearTimeout(reminderTimers.get(bookingKey));
      reminderTimers.delete(bookingKey);
    }
    if (delay <= 0) return res.json({ ok: true, skipped: true });

    const timer = setTimeout(async () => {
      try {
        await sendEmail({
          to: email,
          subject: 'Напоминание о занятии',
          text: `Напоминание: через час занятие "${className}".`,
        });
      } finally {
        reminderTimers.delete(bookingKey);
      }
    }, delay);
    reminderTimers.set(bookingKey, timer);
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'notify_failed' });
  }
});

app.post('/api/notify/reminder/cancel', (req, res) => {
  if (!verifySync(req)) return res.status(403).json({ error: 'sync_only' });
  const bookingKey = String(req.body?.bookingKey || '').trim();
  if (!bookingKey) return res.status(400).json({ error: 'booking_key_required' });
  if (reminderTimers.has(bookingKey)) {
    clearTimeout(reminderTimers.get(bookingKey));
    reminderTimers.delete(bookingKey);
  }
  return res.json({ ok: true });
});

// GET /api/studio – для админки (и для мобильного приложения с sync‑токеном)
app.get('/api/studio', async (req, res) => {
  try {
    if (pgEnabled && pool) {
      // 1. Направления
      const directionsRes = await pool.query('SELECT id_направления as id, "Название" as name, "Описание" as description FROM "Направления"');
      // 2. Тренеры с именами
      const trainersRes = await pool.query(`
        SELECT t.id_тренера as id, u."Имя" || ' ' || u."Фамилия" as name, t."Специализация" as specialization
        FROM "Тренеры" t
        JOIN "Пользователи" u ON t.id_пользователя = u.id_пользователя
      `);
      // 3. Занятия (шаблоны)
      const classesRes = await pool.query(`
        SELECT 
          z.id_занятия as id,
          d."Название" as direction_name,
          z.id_тренера as trainer_id,
          z."Длительность_минут" as duration,
          z."Цена" as price
        FROM "Занятия" z
        JOIN "Направления" d ON z.id_направления = d.id_направления
      `);
      // 4. Расписание – для извлечения времени
      const scheduleRes = await pool.query(`
        SELECT id_занятия as class_id, "Время_начала" as start_time
        FROM "Расписание"
        ORDER BY "Время_начала"
      `);

      // Сопоставляем id занятия со временем (берём первое расписание для каждого занятия)
      const classTimeMap = new Map();
      scheduleRes.rows.forEach(s => {
        if (s.class_id && !classTimeMap.has(s.class_id)) {
          const timeStr = new Date(s.start_time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
          classTimeMap.set(s.class_id, timeStr);
        }
      });

      // Форматируем classTemplates для фронтенда (админка и мобилка)
      const formattedClasses = classesRes.rows.map(c => {
        const trainer = trainersRes.rows.find(t => t.id === c.trainer_id);
        const time = classTimeMap.get(c.id) || '13:00';
        return {
          id: c.id,
          time: time,
          durationMinutes: c.duration,
          direction: c.direction_name,      // Для админки
          className: c.direction_name,      // Для мобилки (она может ожидать className)
          trainerName: trainer ? trainer.name : 'Неизвестный тренер',
          availableSpots: 20
        };
      });

      const studioData = {
        directions: directionsRes.rows,
        trainers: trainersRes.rows,
        classTemplates: formattedClasses,
        schedule: scheduleRes.rows,
        bookings: [],   // при желании загрузите из таблицы "Записи"
        dialogs: {}
      };

      // Возвращаем данные для ЛЮБОГО запроса (и для админки, и для мобилки с X-Sync-Token)
      return res.json(studioData);
    }

    // ========== СТАРОЕ ПОВЕДЕНИЕ (резерв, если БД не подключена) ==========
    let data = readData();
    data = ensureAccounts(data);
    data = await buildStudioWithDialogs(data);
    if (verifySync(req)) return res.json(stripAccounts(data));
    const v = verifyJwt(req);
    if (v.ok && v.payload.role === 'admin') return res.json(stripAccounts(data));
    if (v.ok && v.payload.role === 'trainer' && v.payload.trainerName) {
      return res.json(filterForTrainer(data, v.payload.trainerName));
    }
    return res.status(403).json({ error: 'forbidden' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'server_error' });
  }
});

/** Сообщение в чат (мобильное приложение через X-Sync-Token). */
app.post('/api/chat/message', async (req, res) => {
  try {
    if (!verifySync(req)) {
      return res.status(403).json({ error: 'sync_only' });
    }
    const trainerName = String(req.body?.trainerName || '').trim();
    const author = String(req.body?.author || 'Ученик').trim() || 'Ученик';
    const text = String(req.body?.text || '').trim();
    if (!trainerName) return res.status(400).json({ error: 'trainer_required' });
    if (!text) return res.status(400).json({ error: 'empty_text' });

    await saveChatMessage({ trainerName, author, text });
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'message_failed' });
  }
});

/** Сообщение от тренера в свой чат с учениками */
app.post('/api/trainer/message', async (req, res) => {
  try {
    const v = verifyJwt(req);
    if (!v.ok || v.payload.role !== 'trainer' || !v.payload.trainerName) {
      return res.status(403).json({ error: 'trainer_only' });
    }
    const text = (req.body && req.body.text) || '';
    if (!String(text).trim()) {
      return res.status(400).json({ error: 'empty_text' });
    }
    const name = v.payload.trainerName;
    await saveChatMessage({
      trainerName: name,
      author: 'Тренер',
      text: String(text).trim(),
    });
    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'message_failed' });
  }
});

app.post('/api/classes', async (req, res) => {
  try {
    // Проверка, что только админ может добавлять занятия
    const v = verifyJwt(req);
    if (!v.ok || v.payload.role !== 'admin') {
      return res.status(403).json({ error: 'only_admin' });
    }

    const { directionName, trainerId, duration, price } = req.body;
    if (!directionName || !trainerId) {
      return res.status(400).json({ error: 'missing_fields' });
    }

    // Находим ID направления по имени
    const dirRes = await pool.query(
      'SELECT "id_направления" FROM "Направления" WHERE "Название" = $1',
      [directionName]
    );
    if (dirRes.rows.length === 0) {
      return res.status(400).json({ error: 'direction_not_found' });
    }
    const directionId = dirRes.rows[0].id_направления;

    // Получаем ID статуса "активно"
    const statusRes = await pool.query(
      'SELECT "id_статуса" FROM "Статус_направления_и_занятия" WHERE "Название_статуса" = $1',
      ['активно']
    );
    const statusId = statusRes.rows[0]?.id_статуса || 1;

    const result = await pool.query(
      `INSERT INTO "Занятия" ("id_тренера", "id_направления", "id_статуса", "Длительность_минут", "Цена")
       VALUES ($1, $2, $3, $4, $5) RETURNING "id_занятия"`,
      [trainerId, directionId, statusId, duration || 55, price || 0]
    );

    res.status(201).json({ ok: true, classId: result.rows[0].id_занятия });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'db_error' });
  }
});

app.put('/api/studio', async (req, res) => {
  try {
    console.log('PUT /api/studio вызван');
    const v = verifyJwt(req);
    if (!v.ok || v.payload.role !== 'admin') {
      return res.status(403).json({ error: 'forbidden' });
    }

    const { classTemplates } = req.body;
    if (!classTemplates || !Array.isArray(classTemplates)) {
      return res.status(400).json({ error: 'invalid data' });
    }

    for (const ct of classTemplates) {
      // Определяем название направления
      const directionName = ct.direction || ct.className;
      if (!directionName) {
        console.error('Нет названия направления для занятия', ct);
        return res.status(400).json({ error: 'Missing direction' });
      }

      // Проверяем, существует ли уже занятие с таким id (если id - число)
      let exists = false;
      if (typeof ct.id === 'number') {
        const check = await pool.query('SELECT id_занятия FROM "Занятия" WHERE id_занятия = $1', [ct.id]);
        if (check.rows.length > 0) {
          exists = true;
        }
      }

      if (!exists) {
        // Новое занятие: ищем направление
        const dirRes = await pool.query('SELECT id_направления FROM "Направления" WHERE "Название" = $1', [directionName]);
        if (dirRes.rows.length === 0) {
          return res.status(400).json({ error: `Direction '${directionName}' not found` });
        }
        const directionId = dirRes.rows[0].id_направления;

        // Ищем тренера по имени
        const trainerName = ct.trainerName;
        const trainerRes = await pool.query(
          `SELECT t.id_тренера FROM "Тренеры" t
           JOIN "Пользователи" u ON t.id_пользователя = u.id_пользователя
           WHERE u."Имя" || ' ' || u."Фамилия" = $1`,
          [trainerName]
        );
        if (trainerRes.rows.length === 0) {
          return res.status(400).json({ error: `Trainer '${trainerName}' not found` });
        }
        const trainerId = trainerRes.rows[0].id_тренера;

        // Статус "активно"
        const statusRes = await pool.query('SELECT id_статуса FROM "Статус_направления_и_занятия" WHERE "Название_статуса" = $1', ['активно']);
        const statusId = statusRes.rows[0]?.id_статуса || 1;

        // Вставляем новое занятие
        await pool.query(
          `INSERT INTO "Занятия" (id_тренера, id_направления, id_статуса, "Длительность_минут", "Цена")
           VALUES ($1, $2, $3, $4, $5)`,
          [trainerId, directionId, statusId, ct.durationMinutes || 55, 0]
        );
        console.log('Добавлено новое занятие:', directionName, trainerName);
      }
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('Ошибка в PUT /api/studio:', err);
    res.status(500).json({ error: 'update_failed', details: err.message });
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
    const tokenPayload = {
      role: 'student',
      userId: user.id_пользователя,
    };
    const token = jwt.sign(tokenPayload, JWT_SECRET, { expiresIn: '14d' });
    res.status(200).json({
      message: 'Вход успешен',
      userId: user.id_пользователя,
      name: firstName,
      firstName,
      phone: user.Телефон ?? '',
      email: userEmail,
      token: token, 
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
  console.log(req.body);
  
  // Принимаем поле login (от фронтенда) или username (на всякий случай)
  const login = req.body.login || req.body.username || '';
  const { password } = req.body;

  console.log('Login attempt:', { login, password });

  // Администратор: логин пустая строка, пароль admin123
  if (login === '' && password === 'admin123') {
    console.log('Admin login success');
    return res.json({ role: 'admin', token: 'fake-token' });
  }

  // Тренер (заглушка): любой непустой логин, пароль trainer123
  if (password === 'trainer123') {
    console.log('Trainer logged in (stub)');
    return res.json({ role: 'trainer', token: 'fake-token' });
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



initPostgres().finally(() => {
  app.listen(PORT, () => {
  console.log(`Studio API: http://localhost:${PORT}`);
  console.log(
    pgEnabled
      ? '  [db] PostgreSQL подключён — мобильный вход и абонементы работают'
      : '  [db] PostgreSQL НЕ подключён — /api/mobile/* вернёт 503. Задайте DATABASE_URL в .env или в среде.'
  );
  console.log(
    stripe
      ? '  [payments] Stripe включён (STRIPE_SECRET_KEY)'
      : '  [payments] без Stripe: абонемент оформляется без внешней оплаты (STRIPE_SECRET_KEY пуст или STRIPE_DISABLED=1)'
  );
  console.log(`  POST /api/auth/login`);
  console.log(`  GET  /PUT/api/studio  (заголовок X-Sync-Token для мобильного приложения)`);
  console.log(`  POST /api/chat/message  (X-Sync-Token)`);
  console.log(`  POST /api/trainer/message  (Bearer, роль trainer)`);
});
});
