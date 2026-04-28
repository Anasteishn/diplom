# Мобильное приложение (Flutter)

## Веб-админка и общие данные

Админ-панель — отдельный проект: **`../dance_school_admin`** (React + API на Node).

1. В папке админки: `npm install` и `npm run dev` (API **:5050**, сайт **:3000**).
2. Приложение при старте запрашивает `GET /api/studio` с заголовком **`X-Sync-Token`** (по умолчанию `dev-sync-token`, должен совпадать с `MOBILE_SYNC_TOKEN` на сервере).
3. Запись/отмена и правки администратора сохраняются через `PUT /api/studio`, а сообщения чатов — через `POST /api/chat/message`.
4. Если на сервере задан `DATABASE_URL`, сообщения чатов сохраняются в PostgreSQL (таблица `chat_messages`).

**Эмулятор Android:** по умолчанию используются `http://10.0.2.2:5050` и `http://10.0.2.2:3000`.

**Телефон в Wi‑Fi:** укажите IP вашего ПК:

```bash
flutter run --dart-define=STUDIO_API_URL=http://192.168.x.x:5050 --dart-define=ADMIN_WEB_URL=http://192.168.x.x:3000 --dart-define=STUDIO_SYNC_TOKEN=dev-sync-token
```

**Открыть админку из приложения (с клавиатуры):** `Ctrl+Shift+]` — откроется браузер с `ADMIN_WEB_URL`.

Подробнее — в `dance_school_admin/README.md`.
