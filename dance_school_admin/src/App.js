import React, { useCallback, useEffect, useRef, useState } from 'react';
import './App.css';

const LS_TOKEN = 'jb_token';
const LS_ROLE = 'jb_role';
const LS_TRAINER = 'jb_trainer_name';
const LS_LOGIN = 'jb_login';

function getSession() {
  return {
    token: localStorage.getItem(LS_TOKEN),
    role: localStorage.getItem(LS_ROLE),
    trainerName: localStorage.getItem(LS_TRAINER),
    login: localStorage.getItem(LS_LOGIN),
  };
}

function saveSession({ token, role, trainerName, login }) {
  localStorage.setItem(LS_TOKEN, token);
  localStorage.setItem(LS_ROLE, role);
  if (trainerName) localStorage.setItem(LS_TRAINER, trainerName);
  else localStorage.removeItem(LS_TRAINER);
  localStorage.setItem(LS_LOGIN, login || '');
}

function clearSession() {
  [LS_TOKEN, LS_ROLE, LS_TRAINER, LS_LOGIN].forEach((k) => localStorage.removeItem(k));
}

function emptyStudio() {
  return {
    trainers: [],
    classTemplates: [],
    bookings: [],
    dialogs: {},
  };
}

export default function App() {
  const [session, setSession] = useState(() => getSession());
  const [booting, setBooting] = useState(!!getSession().token);

  useEffect(() => {
    const { token } = getSession();
    if (!token) {
      setBooting(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/studio', {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error('session');
        const data = await res.json();
        const isAdminPayload = Array.isArray(data.trainers);
        const { role } = getSession();
        if (role === 'admin' && !isAdminPayload) throw new Error('role_mismatch');
        if (role === 'trainer' && isAdminPayload) throw new Error('role_mismatch');
        if (!cancelled) setSession(getSession());
      } catch {
        clearSession();
        if (!cancelled) setSession({});
      } finally {
        if (!cancelled) setBooting(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const handleLoginSuccess = (payload) => {
    saveSession(payload);
    setSession(getSession());
  };

  const handleLogout = () => {
    clearSession();
    setSession({});
  };

  if (booting) {
    return (
      <div className="app app-center">
        <p className="loading-msg">Проверка сессии…</p>
      </div>
    );
  }

  if (!session.token) {
    return <LoginPage onSuccess={handleLoginSuccess} />;
  }

  if (session.role === 'admin') {
    return <AdminCabinet token={session.token} login={session.login} onLogout={handleLogout} />;
  }

  if (session.role === 'trainer') {
    return (
      <TrainerCabinet
        token={session.token}
        login={session.login}
        trainerName={session.trainerName}
        onLogout={handleLogout}
      />
    );
  }

  clearSession();
  return <LoginPage onSuccess={handleLoginSuccess} />;
}

function LoginPage({ onSuccess }) {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setErr('');
    setLoading(true);
    try {
      const payload = {
        login: login.trim(),
        password,
      };
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setErr(data.error === 'invalid_credentials' ? 'Неверный логин или пароль' : 'Ошибка входа');
        return;
      }
      onSuccess({
        token: data.token,
        role: data.role,
        trainerName: data.trainerName,
        login: data.login,
      });
    } catch {
      setErr('Нет связи с сервером');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app app-login">
      <div className="login-card">
        <h1>Танцы И Только</h1>
        <p className="login-subtitle">Вход в панель</p>
        <form onSubmit={submit}>
          <div className="form-row">
            <label>Логин</label>
            <input
              autoComplete="username"
              value={login}
              onChange={(e) => setLogin(e.target.value)}
              placeholder="логин тренера (для администратора оставьте пустым)"
            />
          </div>
          <div className="form-row">
            <label>Пароль</label>
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          {err ? <div className="login-error">{err}</div> : null}
          <div className="login-actions">
            <button type="submit" className="btn-primary btn-block" disabled={loading}>
              {loading ? 'Вход…' : 'Войти'}
            </button>
          </div>
        </form>
        <p className="login-hint">
          Администратор: оставьте логин пустым, пароль <code>admin123</code>
          <br />
          Тренеры: пароль <code>trainer123</code>, логины — в README проекта.
        </p>
      </div>
    </div>
  );
}

function AdminCabinet({ token, login, onLogout }) {
  const [studio, setStudio] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('schedule');
  const saveTimer = useRef(null);

  const authHeaders = { Authorization: `Bearer ${token}` };

  const scheduleSave = useCallback(
    (nextStudio) => {
      setStudio(nextStudio);
      if (saveTimer.current) clearTimeout(saveTimer.current);
      saveTimer.current = setTimeout(async () => {
        try {
          const res = await fetch('/api/studio', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', ...authHeaders },
            body: JSON.stringify(nextStudio),
          });
          if (!res.ok) throw new Error('save failed');
        } catch (e) {
          console.error(e);
          setError('Не удалось сохранить. Проверьте сессию администратора.');
        }
      }, 450);
    },
    [token]
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/studio', { headers: authHeaders });
        if (res.status === 401) {
          clearSession();
          window.location.reload();
          return;
        }
        if (!res.ok) throw new Error('load failed');
        const data = await res.json();
        if (!cancelled) {
          setStudio({
            trainers: data.trainers || [],
            classTemplates: data.classTemplates || [],
            bookings: data.bookings || [],
            dialogs: data.dialogs || {},
          });
        }
      } catch (e) {
        console.error(e);
        if (!cancelled) {
          setError('Не удалось загрузить данные.');
          setStudio(emptyStudio());
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      if (saveTimer.current) clearTimeout(saveTimer.current);
    };
  }, [token]);

  const renderContent = () => {
    if (!studio) return null;
    switch (activeTab) {
      case 'schedule':
        return <ScheduleManager studio={studio} onChange={scheduleSave} />;
      case 'bookings':
        return <BookingsView bookings={studio.bookings} />;
      case 'trainers':
        return <TrainersManager studio={studio} onChange={scheduleSave} />;
      case 'reports':
        return <ReportsView studio={studio} />;
      default:
        return <ScheduleManager studio={studio} onChange={scheduleSave} />;
    }
  };

  if (loading) {
    return (
      <div className="app">
        <p className="loading-msg">Загрузка…</p>
      </div>
    );
  }

  return (
    <div className="app">
      <header className="header">
        <h1>Танцы И Только — администратор</h1>
        <div className="admin-info">
          <span className="user-pill">{login}</span>
          <button type="button" className="logout-btn" onClick={onLogout}>
            Выйти
          </button>
        </div>
      </header>

      {error ? <div className="banner-error">{error}</div> : null}

      <div className="container">
        <nav className="sidebar">
          <ul>
            <li className={activeTab === 'schedule' ? 'active' : ''} onClick={() => setActiveTab('schedule')}>
              Расписание
            </li>
            <li className={activeTab === 'bookings' ? 'active' : ''} onClick={() => setActiveTab('bookings')}>
              Все записи
            </li>
            <li className={activeTab === 'trainers' ? 'active' : ''} onClick={() => setActiveTab('trainers')}>
              Тренеры
            </li>
            <li className={activeTab === 'reports' ? 'active' : ''} onClick={() => setActiveTab('reports')}>
              Отчёты
            </li>
          </ul>
        </nav>

        <main className="content">{renderContent()}</main>
      </div>
    </div>
  );
}

function TrainerCabinet({ token, login, trainerName, onLogout }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('bookings');
  const [msgText, setMsgText] = useState('');
  const [sending, setSending] = useState(false);

  const authHeaders = { Authorization: `Bearer ${token}` };

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/studio', { headers: authHeaders });
      if (res.status === 401) {
        clearSession();
        window.location.reload();
        return;
      }
      if (!res.ok) throw new Error('load');
      const j = await res.json();
      setData(j);
      setError('');
    } catch {
      setError('Не удалось загрузить данные');
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    load();
  }, [load]);

  const sendMessage = async (e) => {
    e.preventDefault();
    if (!msgText.trim() || sending) return;
    setSending(true);
    try {
      const res = await fetch('/api/trainer/message', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...authHeaders },
        body: JSON.stringify({ text: msgText.trim() }),
      });
      if (!res.ok) throw new Error('send');
      setMsgText('');
      await load();
    } catch {
      setError('Не удалось отправить сообщение');
    } finally {
      setSending(false);
    }
  };

  if (loading) {
    return (
      <div className="app">
        <p className="loading-msg">Загрузка кабинета…</p>
      </div>
    );
  }

  const bookings = data?.bookings || [];
  const thread = (data?.dialogs && trainerName && data.dialogs[trainerName]) || [];

  return (
    <div className="app">
      <header className="header header-trainer">
        <div>
          <h1>Кабинет тренера</h1>
          <p className="trainer-sub">{trainerName || login}</p>
        </div>
        <div className="admin-info">
          <span className="user-pill">{login}</span>
          <button type="button" className="logout-btn" onClick={onLogout}>
            Выйти
          </button>
        </div>
      </header>

      {error ? <div className="banner-error">{error}</div> : null}

      <div className="container">
        <nav className="sidebar">
          <ul>
            <li className={activeTab === 'bookings' ? 'active' : ''} onClick={() => setActiveTab('bookings')}>
              Мои записи ({bookings.length})
            </li>
            <li className={activeTab === 'chats' ? 'active' : ''} onClick={() => setActiveTab('chats')}>
              Чаты с учениками
            </li>
          </ul>
        </nav>

        <main className="content">
          {activeTab === 'bookings' ? (
            <div>
              <div className="content-header">
                <h2>Записи ко мне на занятия</h2>
              </div>
              <table className="table">
                <thead>
                  <tr>
                    <th>Ученик</th>
                    <th>Занятие</th>
                    <th>Дата</th>
                    <th>Время</th>
                  </tr>
                </thead>
                <tbody>
                  {bookings.length === 0 ? (
                    <tr>
                      <td colSpan={4}>Пока нет записей</td>
                    </tr>
                  ) : (
                    bookings.map((b, i) => (
                      <tr key={i}>
                        <td>{b.student || 'Ученик (приложение)'}</td>
                        <td>{b.className}</td>
                        <td>{formatDateRu(b.date)}</td>
                        <td>{b.time}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          ) : (
            <div>
              <div className="content-header">
                <h2>Диалог с учениками</h2>
              </div>
              <p className="hint">Сообщения из мобильного приложения и ваши ответы.</p>
              <div className="chat-thread">
                {thread.length === 0 ? (
                  <p className="muted">Пока нет сообщений</p>
                ) : (
                  thread.map((m, i) => (
                    <div
                      key={i}
                      className={`chat-bubble ${m.author === 'Тренер' ? 'chat-bubble--trainer' : 'chat-bubble--student'}`}
                    >
                      <div className="chat-meta">
                        {m.author} · {formatDateTimeRu(m.createdAt)}
                      </div>
                      <div>{m.text}</div>
                    </div>
                  ))
                )}
              </div>
              <form className="chat-compose" onSubmit={sendMessage}>
                <input
                  value={msgText}
                  onChange={(e) => setMsgText(e.target.value)}
                  placeholder="Ответить ученику…"
                />
                <button type="submit" className="btn-primary" disabled={sending}>
                  Отправить
                </button>
              </form>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

function formatDateTimeRu(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString('ru-RU');
}

function ScheduleManager({ studio, onChange }) {
  const { classTemplates, trainers } = studio;
  const [showAddForm, setShowAddForm] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState({
    time: '12:00',
    durationMinutes: 55,
    className: 'Strip',
    trainerName: '',
    availableSpots: 20,
  });

  const trainerOptions = trainers.length ? trainers.map((t) => t.name) : [''];

  const updateTemplates = (nextList) => {
    onChange({ ...studio, classTemplates: nextList });
  };

  const addClass = () => {
    const id = String(Date.now());
    const row = {
      id,
      time: form.time,
      durationMinutes: Number(form.durationMinutes) || 55,
      className: form.className,
      availableSpots: Number(form.availableSpots) || 10,
      trainerName: form.trainerName || trainerOptions[0],
    };
    updateTemplates([...classTemplates, row]);
    setShowAddForm(false);
    setForm({
      time: '12:00',
      durationMinutes: 55,
      className: 'Strip',
      trainerName: '',
      availableSpots: 20,
    });
  };

  const deleteClass = (id) => {
    updateTemplates(classTemplates.filter((c) => c.id !== id));
  };

  const saveEdit = (id, patch) => {
    updateTemplates(classTemplates.map((c) => (c.id === id ? { ...c, ...patch } : c)));
    setEditingId(null);
  };

  return (
    <div>
      <div className="content-header">
        <h2>Шаблоны занятий</h2>
        <button className="btn-primary" onClick={() => setShowAddForm(true)}>
          + Добавить занятие
        </button>
      </div>
      <p className="hint">Изменения синхронизируются с мобильным приложением.</p>

      {showAddForm && (
        <div className="form-card">
          <h3>Новое занятие</h3>
          <div className="form-row">
            <label>Время</label>
            <input
              type="time"
              value={form.time}
              onChange={(e) => setForm({ ...form, time: e.target.value })}
            />
          </div>
          <div className="form-row">
            <label>Длительность (мин)</label>
            <input
              type="number"
              value={form.durationMinutes}
              onChange={(e) => setForm({ ...form, durationMinutes: e.target.value })}
            />
          </div>
          <div className="form-row">
            <label>Направление</label>
            <input
              type="text"
              value={form.className}
              onChange={(e) => setForm({ ...form, className: e.target.value })}
            />
          </div>
          <div className="form-row">
            <label>Тренер</label>
            <select
              value={form.trainerName || trainerOptions[0]}
              onChange={(e) => setForm({ ...form, trainerName: e.target.value })}
            >
              {trainerOptions.map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </div>
          <div className="form-row">
            <label>Макс. мест</label>
            <input
              type="number"
              value={form.availableSpots}
              onChange={(e) => setForm({ ...form, availableSpots: e.target.value })}
            />
          </div>
          <div className="form-actions">
            <button className="btn-secondary" onClick={() => setShowAddForm(false)}>
              Отмена
            </button>
            <button className="btn-primary" onClick={addClass}>
              Сохранить
            </button>
          </div>
        </div>
      )}

      <table className="table">
        <thead>
          <tr>
            <th>Время</th>
            <th>Мин</th>
            <th>Направление</th>
            <th>Тренер</th>
            <th>Мест</th>
            <th>Действия</th>
          </tr>
        </thead>
        <tbody>
          {classTemplates.map((c) =>
            editingId === c.id ? (
              <EditTemplateRow
                key={c.id}
                row={c}
                trainerOptions={trainerOptions}
                onSave={(patch) => saveEdit(c.id, patch)}
                onCancel={() => setEditingId(null)}
              />
            ) : (
              <tr key={c.id}>
                <td>{c.time}</td>
                <td>{c.durationMinutes}</td>
                <td>{c.className}</td>
                <td>{c.trainerName}</td>
                <td>{c.availableSpots}</td>
                <td>
                  <button className="btn-icon" type="button" onClick={() => setEditingId(c.id)}>
                    Изменить
                  </button>
                  <button className="btn-icon" type="button" onClick={() => deleteClass(c.id)}>
                    Удалить
                  </button>
                </td>
              </tr>
            )
          )}
        </tbody>
      </table>
    </div>
  );
}

function EditTemplateRow({ row, trainerOptions, onSave, onCancel }) {
  const [local, setLocal] = useState({ ...row });
  return (
    <tr>
      <td>
        <input
          type="time"
          value={local.time}
          onChange={(e) => setLocal({ ...local, time: e.target.value })}
        />
      </td>
      <td>
        <input
          type="number"
          style={{ width: 70 }}
          value={local.durationMinutes}
          onChange={(e) => setLocal({ ...local, durationMinutes: Number(e.target.value) })}
        />
      </td>
      <td>
        <input
          type="text"
          value={local.className}
          onChange={(e) => setLocal({ ...local, className: e.target.value })}
        />
      </td>
      <td>
        <select
          value={local.trainerName}
          onChange={(e) => setLocal({ ...local, trainerName: e.target.value })}
        >
          {trainerOptions.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </td>
      <td>
        <input
          type="number"
          style={{ width: 70 }}
          value={local.availableSpots}
          onChange={(e) => setLocal({ ...local, availableSpots: Number(e.target.value) })}
        />
      </td>
      <td>
        <button className="btn-primary" type="button" onClick={() => onSave(local)}>
          OK
        </button>
        <button className="btn-secondary" type="button" onClick={onCancel}>
          Отмена
        </button>
      </td>
    </tr>
  );
}

function BookingsView({ bookings }) {
  return (
    <div>
      <div className="content-header">
        <h2>Все записи (приложение)</h2>
      </div>
      <table className="table">
        <thead>
          <tr>
            <th>Ученик</th>
            <th>Занятие</th>
            <th>Тренер</th>
            <th>Дата</th>
            <th>Время</th>
          </tr>
        </thead>
        <tbody>
          {bookings.length === 0 ? (
            <tr>
              <td colSpan={5}>Пока нет записей</td>
            </tr>
          ) : (
            bookings.map((b, i) => (
              <tr key={i}>
                <td>{b.student || 'Ученик (приложение)'}</td>
                <td>{b.className}</td>
                <td>{b.trainerName}</td>
                <td>{formatDateRu(b.date)}</td>
                <td>{b.time}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}

function formatDateRu(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString('ru-RU');
}

function TrainersManager({ studio, onChange }) {
  const { trainers } = studio;
  const [showAdd, setShowAdd] = useState(false);
  const [editingIndex, setEditingIndex] = useState(null);
  const [form, setForm] = useState({ name: '', danceStyle: '', phone: '' });

  const updateTrainers = (next) => {
    onChange({ ...studio, trainers: next });
  };

  const addTrainer = () => {
    if (!form.name.trim()) return;
    updateTrainers([
      ...trainers,
      { name: form.name.trim(), danceStyle: form.danceStyle.trim() || '—', phone: form.phone.trim() || '' },
    ]);
    setForm({ name: '', danceStyle: '', phone: '' });
    setShowAdd(false);
  };

  const removeTrainer = (index) => {
    updateTrainers(trainers.filter((_, i) => i !== index));
  };

  const saveTrainer = (index, row) => {
    const next = [...trainers];
    next[index] = row;
    updateTrainers(next);
    setEditingIndex(null);
  };

  return (
    <div>
      <div className="content-header">
        <h2>Тренеры</h2>
        <button className="btn-primary" onClick={() => setShowAdd(true)}>
          + Добавить тренера
        </button>
      </div>
      <p className="hint">
        После добавления тренера вручную создайте для него учётную запись в <code>server/data.json</code> →{' '}
        <code>accounts</code> (или удалите файл accounts и перезапустите сервер для автосидирования заново).
      </p>

      {showAdd && (
        <div className="form-card">
          <h3>Новый тренер</h3>
          <div className="form-row">
            <label>Имя</label>
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </div>
          <div className="form-row">
            <label>Направление</label>
            <input
              value={form.danceStyle}
              onChange={(e) => setForm({ ...form, danceStyle: e.target.value })}
            />
          </div>
          <div className="form-row">
            <label>Телефон</label>
            <input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
          </div>
          <div className="form-actions">
            <button className="btn-secondary" onClick={() => setShowAdd(false)}>
              Отмена
            </button>
            <button className="btn-primary" onClick={addTrainer}>
              Сохранить
            </button>
          </div>
        </div>
      )}

      <div className="trainers-grid">
        {trainers.map((t, index) =>
          editingIndex === index ? (
            <EditTrainerCard
              key={index}
              trainer={t}
              onSave={(row) => saveTrainer(index, row)}
              onCancel={() => setEditingIndex(null)}
            />
          ) : (
            <div key={index} className="trainer-card">
              <div className="trainer-avatar">👤</div>
              <h3>{t.name}</h3>
              <p>Направление: {t.danceStyle}</p>
              <p>Телефон: {t.phone || '—'}</p>
              <div className="card-actions">
                <button className="btn-icon" type="button" onClick={() => setEditingIndex(index)}>
                  Изменить
                </button>
                <button className="btn-icon" type="button" onClick={() => removeTrainer(index)}>
                  Удалить
                </button>
              </div>
            </div>
          )
        )}
      </div>
    </div>
  );
}

function EditTrainerCard({ trainer, onSave, onCancel }) {
  const [local, setLocal] = useState({ ...trainer });
  return (
    <div className="trainer-card">
      <h3>Редактирование</h3>
      <div className="form-row">
        <label>Имя</label>
        <input value={local.name} onChange={(e) => setLocal({ ...local, name: e.target.value })} />
      </div>
      <div className="form-row">
        <label>Направление</label>
        <input
          value={local.danceStyle}
          onChange={(e) => setLocal({ ...local, danceStyle: e.target.value })}
        />
      </div>
      <div className="form-row">
        <label>Телефон</label>
        <input value={local.phone || ''} onChange={(e) => setLocal({ ...local, phone: e.target.value })} />
      </div>
      <div className="card-actions">
        <button className="btn-primary" type="button" onClick={() => onSave(local)}>
          OK
        </button>
        <button className="btn-secondary" type="button" onClick={onCancel}>
          Отмена
        </button>
      </div>
    </div>
  );
}

function ReportsView({ studio }) {
  const { classTemplates, bookings, trainers } = studio;
  const totalSpots = classTemplates.reduce((s, c) => s + (c.availableSpots || 0), 0);
  const byTrainer = {};
  (bookings || []).forEach((b) => {
    const k = b.trainerName || '—';
    byTrainer[k] = (byTrainer[k] || 0) + 1;
  });
  const topTrainers = Object.entries(byTrainer).sort((a, b) => b[1] - a[1]);

  return (
    <div>
      <div className="content-header">
        <h2>Отчётность</h2>
      </div>
      <div className="reports-grid">
        <div className="report-card">
          <h3>Обзор</h3>
          <p>Тренеров: {trainers.length}</p>
          <p>Слотов в шаблоне дня: {classTemplates.length}</p>
          <p>Суммарно мест (по шаблону): {totalSpots}</p>
          <p>Записей из приложения: {bookings.length}</p>
        </div>
        <div className="report-card">
          <h3>Загрузка</h3>
          <p>
            Среднее мест на занятие:{' '}
            {classTemplates.length ? Math.round(totalSpots / classTemplates.length) : 0}
          </p>
        </div>
        <div className="report-card report-card--wide">
          <h3>Записи по тренерам</h3>
          {topTrainers.length === 0 ? (
            <p className="muted">Нет данных</p>
          ) : (
            <table className="table table-compact">
              <tbody>
                {topTrainers.map(([name, n]) => (
                  <tr key={name}>
                    <td>{name}</td>
                    <td>{n} запис.</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}
