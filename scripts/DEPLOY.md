# Регламент деплоя SIEM Source Tracker

> **Легаси-регламент.** Основной способ деплоя теперь — просто `docker compose up -d`
> на prod-хосте (см. README в корне репозитория). Скрипты этого регламента
> (`deploy-prod.ps1`, `deploy_app.sh`) сохранены в `scripts/` и пока не удаляются.
>
> Реальные значения prod-хоста, пользователя и пути к SSH-ключу **намеренно не
> хранятся в этом публичном репозитории** — в примерах ниже используются
> плейсхолдеры `<prod-host>`, `<prod-user>`, `C:\path\to\...`; реальные значения
> передаются параметрами `deploy-prod.ps1` (`-ProdHost`/`-ProdUser`/`-SshKey`).

## 1. Назначение

Документ описывает порядок доставки доработок приложения **SIEM Source Tracker** с локальной dev-машины Windows на удаленный Linux-хост в корпоративной лаборатории.

Цель регламента:

- обновлять приложение без потери данных;
- не собирать приложение на prod-хосте;
- перед каждым обновлением делать резервную копию БД;
- применять миграции Prisma штатным способом;
- иметь возможность повторить деплой с уже запушенного в реестр образа;
- иметь возможность отката.

---

## 2. Общая схема

```text
Windows dev
  ├─ разработка
  ├─ проверка локально
  ├─ docker build -t ngmaibulat/usiem-tracker:<tag> -t ngmaibulat/usiem-tracker:latest .
  └─ docker push (оба тега)             # в реестр (Docker Hub)

Linux prod
  ├─ pg_dump БД
  ├─ docker compose pull app            # тянет :latest из реестра
  ├─ docker compose run --rm migrate    # одноразовая миграция схемы
  ├─ docker compose up -d
  └─ проверка приложения
```

Prod всегда запускает тег **`latest`** (захардкожен в `docker-compose.yml`);
версионный тег `<tag>` пушится рядом с ним и служит для отката (см. раздел 20).

Образ доставляется через **реестр** (`docker push` на dev → `docker compose
pull` на prod), а не tar-архивом. Образ `ngmaibulat/usiem-tracker` **публичный**,
поэтому prod-хосту `docker login` не нужен; для `docker push` на dev-машине
логин в реестр под этим namespace обязателен.

Если деплой прервался уже после `docker push`, повторный запуск можно выполнить
без пересборки — образ уже в реестре:

```powershell
-NoBuild
```

В этом режиме `docker build`/`docker push` не выполняются — prod просто заново
подтянет текущий `latest` из реестра.

---

## 3. Структура prod-директории

На Linux prod приложение размещено в:

```bash
/opt/siem-source-tracker
```

Рекомендуемая структура:

```text
/opt/siem-source-tracker/          # = содержимое репозитория siem-tracker-deploy
  docker-compose.yml
  nginx/
    conf.d/app.conf                # справочный шаблон (НЕ монтируется — см. §6)
  .env
  deploy_app.sh
  backups/
```

Содержимое репозитория **siem-tracker-deploy** (`docker-compose.yml`, `nginx/` и
`scripts/deploy_app.sh`) копируется в `/opt/siem-source-tracker/` (скрипт — в корень
app-каталога, не в подкаталог `scripts/`), поэтому compose
запускается без флага `-f` (`docker-compose.yml` берется по умолчанию), а
`deploy_app.sh` оказывается по ожидаемому пути. Каталог `releases/` для
tar-архивов больше не нужен — образ тянется из реестра.

Назначение каталогов:

| Путь | Назначение |
|---|---|
| `/opt/siem-source-tracker/docker-compose.yml` | Compose-конфигурация prod-окружения (из репозитория siem-tracker-deploy) |
| `/opt/siem-source-tracker/nginx/` | Справочный шаблон конфигурации прокси (рабочий конфиг и сертификаты живут в томах `proxy_conf` / `proxy_certs`, см. §6) |
| `/opt/siem-source-tracker/.env` | Runtime-переменные приложения |
| `/opt/siem-source-tracker/deploy_app.sh` | Скрипт деплоя на Linux prod (из репозитория siem-tracker-deploy) |
| `/opt/siem-source-tracker/backups/` | Бэкапы PostgreSQL перед деплоем |

Данные PostgreSQL хранятся в Docker volume:

```text
siem-source-tracker_postgres_data
```

---

## 4. Что запрещено на prod

Не выполнять без осознанной необходимости:

```bash
docker compose down -v
```

```bash
docker volume rm siem-source-tracker_postgres_data
```

```bash
pnpm exec prisma migrate reset
```

```bash
docker system prune --volumes
```

Эти команды могут удалить данные PostgreSQL.

---

## 5. Prod `.env`

Файл:

```bash
/opt/siem-source-tracker/.env
```

Пример:

```env
COMPOSE_PROJECT_NAME=siem-source-tracker
APP_SECRET=your-long-secret
TARGET_DATE=2026-06-15
APP_URL=https://siem.example.local
# Мастер-ключ Meilisearch (>= 16 байт) — обязателен, т.к. сервис стартует с
# MEILI_ENV=production. Сгенерировать: openssl rand -base64 32
MEILI_MASTER_KEY=your-meili-master-key
# Необязательно: общий секрет для cron-эндпоинта ежедневных снапшотов (FR-14).
# SNAPSHOT_TOKEN=your-snapshot-token
```

Шаблон со всеми ключами лежит в этом репозитории — `example.env`
(`cp example.env .env`). Тег образа в `.env` не задаётся: compose-файл
запускает `ngmaibulat/usiem-tracker:latest` (оставшаяся от старых версий строка
`APP_IMAGE_TAG=` в prod `.env` безвредна — её можно удалить).

Назначение переменных:

| Переменная | Назначение |
|---|---|
| `COMPOSE_PROJECT_NAME` | фиксирует имя Docker Compose проекта |
| `APP_SECRET` | секрет приложения |
| `TARGET_DATE` | целевой срок прогноза |
| `APP_URL` | публичный HTTPS-адрес (для ссылок в письмах) — за nginx это `https://<host>` |
| `MEILI_MASTER_KEY` | мастер-ключ Meilisearch (>= 16 байт), обязателен при `MEILI_ENV=production` |
| `SNAPSHOT_TOKEN` | (опц.) секрет cron-эндпоинта ежедневных снапшотов |

---

## 6. Prod `docker-compose.yml`

Prod-конфигурация хранится в этом репозитории (siem-tracker-deploy: файл
`docker-compose.yml` вместе с `nginx/`). Скопируйте содержимое
репозитория на prod в `/opt/siem-source-tracker/` и запускайте `docker compose` из
этого каталога (файл `docker-compose.yml` берется по умолчанию, флаг `-f` не
нужен).

Топология: **nginx (TLS) → app → postgres + redis**. Порты наружу публикует
**только nginx** (80/443); `app`, `postgres` и `redis` доступны лишь во
внутренней сети compose. Приложение запускается из **публичного образа реестра
`ngmaibulat/usiem-tracker:latest`** (`docker compose pull` на prod,
сборка и `docker push` на dev — см. остальные разделы); этот файл ничего не
собирает.

Сервисы файла:

| Сервис | Назначение |
|---|---|
| `postgres` | PostgreSQL 18, том `postgres_data`, healthcheck `pg_isready` |
| `redis` | Опциональный кэш, том `redis_data`, healthcheck `redis-cli ping` |
| `meilisearch` | Поисковый движок, том `meili_data`, только внутренняя сеть. Зарезервирован на будущее — приложение к нему пока не обращается (нет `MEILI_*`-кода), но `MEILI_ENV=production` требует `MEILI_MASTER_KEY` |
| `app` | Приложение из образа `ngmaibulat/usiem-tracker:latest`, тома `app_data` + `app_backups` + `proxy_conf` + `proxy_certs` + `nginx_logs` (ro) + `squid_logs` (ro) + `app_logs`, без публикации портов; исходящий HTTP/HTTPS идёт через `squid` (`HTTP_PROXY`/`HTTPS_PROXY`) |
| `nginx` | Реверс-прокси, терминирует TLS, публикует 80/443; конфиг и сертификаты читает из общих томов `proxy_conf` / `proxy_certs`, логи пишет в том `nginx_logs` |
| `squid` | Исходящий (egress) форвард-прокси (FR-32): через него идут все внешние HTTP/HTTPS-запросы приложения (Telegram, мониторинг доступности, проверка обновлений пакетов, импорт календаря). Конфиг `./squid/squid.conf` (ro), журналы — том `squid_logs`. Портов не публикует; его остановка не блокирует приложение — исходящие функции деградируют |
| `migrate` | Одноразовая миграция схемы (профиль `migrate`) |

**Конфигурация nginx и сертификаты — через общие тома (генерирует мастер
настройки).** Bind-монтирования `./nginx/conf.d` и `./nginx/certs` больше нет;
вместо них четыре именованных тома:

| Том | app (запись) | nginx (чтение) | Содержимое |
|---|---|---|---|
| `proxy_conf` | `/app/nginx` | `/etc/nginx/conf.d` (ro) | `app.conf` — конфиг, сгенерированный мастером настройки |
| `proxy_certs` | `/app/tls` | `/etc/nginx/certs` (ro) | `cert.pem` + `key.pem` из шага «TLS» мастера |
| `nginx_logs` | `/app/nginx-logs` (ro, `NGINX_LOG_DIR`) | `/var/log/nginx` | access.log / error.log как обычные файлы; приложение читает их в просмотрщике журналов `/admin/logs` (только ADMIN) |
| `squid_logs` | `/app/squid-logs` (ro, `SQUID_LOG_DIR`) | squid: `/var/log/squid` | access.log / cache.log исходящего прокси; те же вкладки `/admin/logs`. HTTPS отображается строками `CONNECT host:443` (SSL-bump нет намеренно) |
| `app_logs` | `/app/logs` | — | зарезервирован (приложение пишет в stdout) |

Как это работает:

1. **Первый запуск.** Entrypoint приложения создает временный HTTP-конфиг
   (`app.conf`) в `proxy_conf`, поэтому мастер настройки доступен по
   `http://<host>/` (порт 80) еще до появления сертификатов.
2. **Мастер настройки.** Шаг «TLS» записывает `cert.pem`/`key.pem` в
   `proxy_certs`; шаг «Сводка» генерирует боевой `app.conf` (имена серверов из
   `APP_URL` + SAN сертификата, апстрим `app:3000`) и дает скачать отчет и конфиг.
3. **Применение.** После завершения мастера:

```bash
docker compose exec nginx nginx -s reload
```

> **Миграция существующей установки.** Файлы `fullchain.pem`/`privkey.pem` из
> старого каталога `nginx/certs/` при обновлении не подхватятся: скопируйте их в
> том как `cert.pem`/`key.pem` (`docker compose cp` в контейнер `app` по путям
> `/app/tls/cert.pem` и `/app/tls/key.pem`) либо заново пройдите шаг «TLS»
> мастера. Справочный шаблон конфига остается в `nginx/conf.d/app.conf` (в git);
> скрипт `generate-self-signed.sh` сохранен для ручных установок без мастера.

Так как доступ теперь идет через nginx, в prod `.env` должна быть переменная
`APP_URL` с **HTTPS**-адресом хоста (используется в ссылках из писем), например
`APP_URL=https://siem.example.local`.

> **Об образе и пользователе.** Образ запускается под непривилегированным
> пользователем `node` (uid 1000), имеет `HEALTHCHECK` на `/api/health` и содержит
> `postgresql-client` (`pg_restore`) — это нужно для восстановления legacy
> pg_dump-бэкапов через UI. Тома `app_data`/`app_backups` принадлежат `node`.

Сначала вытянуть свежий `latest` из реестра (`run`/`up` ниже всё равно
подтянут отсутствующий образ, но явный `pull` нагляднее — и без него уже
скачанный старый `latest` не обновится):

```bash
cd /opt/siem-source-tracker
docker compose pull app
```

Запуск одноразовой миграции (перед стартом/обновлением `app`):

```bash
cd /opt/siem-source-tracker
# применить все ожидающие миграции к БД и выйти:
docker compose run --rm migrate
```

`docker compose run` запускает сервис разово, игнорируя профиль, и `--rm`
удаляет контейнер после завершения. Так как `migrate deploy` идемпотентна,
команду безопасно повторять — без новых миграций она ничего не делает.

Одна команда `docker compose run --rm migrate` делает два идемпотентных шага:
применяет миграции **домена** (`DATABASE_URL`) и миграции **control-плана**
(`prisma.control.config.ts`, `CONTROL_DATABASE_URL` или схема `control` той же БД).
Сида админа больше нет: на чистой установке (нет учётных записей) приложение
запускает **Мастер первоначальной настройки** (`/setup`), где создаётся первый
администратор и задаются APP_URL / SMTP / целевая дата / TLS. Поэтому шаг `migrate`
теперь **необязателен** — мастер сам применит схему; он полезен, например, чтобы
заранее смигрировать целевую БД перед переключением data-плана.

Поднять весь стек (nginx + app + postgres + redis):

```bash
cd /opt/siem-source-tracker
docker compose up -d
```

> **Порядок при обновлении схемы:** сначала прогнать `docker compose run --rm
> migrate` (миграции применяются к `DATABASE_URL`), затем
> `docker compose up -d app`.
> Миграции и переключение активного подключения (FR-31) нацеливайте на одну и ту
> же БД: мигрируйте целевую БД до переключения на нее, иначе
> `assertDatabaseReady()` остановит старт приложения.

> **⚠️ Обновление мажорной версии Postgres (16 → 18).** Простая смена тега `image`
> на работающем томе `postgres_data` не сработает: каталог данных Postgres
> несовместим между мажорными версиями, и Postgres 18 откажется стартовать на
> данных, созданных Postgres 16. Для существующей prod-БД нужен перенос данных,
> а не просто смена тега:
>
> Все команды ниже выполняются из каталога `/opt/siem-source-tracker` (где лежит
> `docker-compose.yml`).
>
> 1. Сделать бэкап: `docker compose exec postgres pg_dump -U siem -Fc siem_source_tracker > backup_pre_pg18.dump`.
> 2. Остановить приложение и БД, **удалить старый том** (`docker compose down` + `docker volume rm <project>_postgres_data`).
> 3. Поднять Postgres 18 (`docker compose up -d postgres`), дождаться готовности.
> 4. Восстановить дамп: `docker compose exec -T postgres pg_restore -U siem --no-owner --no-privileges -d siem_source_tracker < backup_pre_pg18.dump`.
> 5. Прогнать миграции одноразовым сервисом (`docker compose run --rm migrate`), затем запустить приложение (`docker compose up -d app`).
>
> Для чистого стенда без ценных данных достаточно `docker compose down -v` и
> повторного `up` с новым образом. Перед обновлением — обязательный бэкап.

В prod-версии не должно быть `build: .` — prod-хост использует готовый Docker
image, а не собирает приложение локально. Проверка:

```bash
cd /opt/siem-source-tracker
docker compose config | grep build
```

Если команда ничего не вывела — `build` отсутствует.

---

## 7. Dev `.dockerignore`

В корне проекта есть файл `.dockerignore` (в git) — отдельно создавать его не
нужно, актуальное содержимое всегда смотрите в репозитории. Он, в частности:

- исключает `node_modules`, `.next`, `.git`, `.env`/`.env.*` (шаблон
  `example.env` под них не попадает и остаётся в контексте), бэкапы/архивы, каталог `data` (SQLite-реестр с секретами), корневые
  `docker-compose*.yml` из build-контекста (prod-стек — compose + `nginx/` +
  сертификаты + deploy-скрипты — теперь живет в отдельном репозитории
  siem-tracker-deploy и в контекст не попадает);
- **сохраняет** `CHANGELOG.md` и `docs/` в образе — страница `/changelog` (и
  `/help`/`/deployment`) читают эти файлы из файловой системы приложения, поэтому
  при правке правил исключения `*.md` обязательно оставляйте исключения
  `!CHANGELOG.md` и `!docs/`.

---

## 8. SSH-доступ с Windows dev на Linux prod

PowerShell-скрипт использует системные команды Windows:

```powershell
ssh
scp
```

Проверить, какой SSH используется:

```powershell
Get-Command ssh
Get-Command scp
```

Обычно ожидается:

```text
C:\Windows\System32\OpenSSH\ssh.exe
C:\Windows\System32\OpenSSH\scp.exe
```

Проверить подключение по ключу:

```powershell
ssh -i "C:\path\to\.ssh\id_ed25519" <prod-user>@<prod-host>
```

Проверить подключение в режиме, который использует deploy-скрипт:

```powershell
ssh -i "C:\path\to\.ssh\id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes <prod-user>@<prod-host> "echo ok"
```

Ожидаемый результат:

```text
ok
```

Проверить `scp`:

```powershell
scp -i "C:\path\to\.ssh\id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes .\scripts\deploy-prod.ps1 <prod-user>@<prod-host>:/tmp/
```

---

## 9. Настройка прав на приватный SSH-ключ Windows

Если Windows OpenSSH пишет:

```text
WARNING: UNPROTECTED PRIVATE KEY FILE!
Bad permissions.
```

нужно ограничить права на файл ключа.

Отключить наследование:

```powershell
icacls "C:\path\to\.ssh\id_ed25519" /inheritance:r
```

Убрать лишние группы:

```powershell
icacls "C:\path\to\.ssh\id_ed25519" /remove "BUILTIN\Users"
icacls "C:\path\to\.ssh\id_ed25519" /remove "Authenticated Users"
icacls "C:\path\to\.ssh\id_ed25519" /remove "Everyone"
```

Узнать имя текущего пользователя:

```powershell
whoami
```

Выдать права текущему пользователю, подставив результат `whoami`:

```powershell
icacls "C:\path\to\.ssh\id_ed25519" /grant:r "DESKTOP-XXXX\username:(F)"
```

Проверить:

```powershell
icacls "C:\path\to\.ssh\id_ed25519"
```

В выводе не должно быть:

```text
BUILTIN\Users
Authenticated Users
Everyone
```

---

## 10. Passwordless sudo для deploy-скрипта

На prod-хосте `deploy-prod.ps1` вызывает:

```bash
sudo -n /opt/siem-source-tracker/deploy_app.sh ...
```

`sudo -n` не спрашивает пароль. Если passwordless sudo не настроен, деплой завершится ошибкой.

Настроить:

```bash
sudo visudo -f /etc/sudoers.d/siem-source-tracker-deploy
```

Содержимое:

```sudoers
<prod-user> ALL=(root) NOPASSWD: /opt/siem-source-tracker/deploy_app.sh *
```

Права:

```bash
sudo chmod 440 /etc/sudoers.d/siem-source-tracker-deploy
```

Проверка:

```bash
sudo -n /opt/siem-source-tracker/deploy_app.sh
```

Ожидаемый результат — сообщение usage, но без запроса пароля:

```text
Usage: /opt/siem-source-tracker/deploy_app.sh <image_tag>
```

---

## 11. Linux prod `deploy_app.sh`

Скрипт версионируется в этом репозитории — `scripts/deploy_app.sh` — и копируется на
prod вместе с остальным содержимым репозитория, поэтому оказывается по пути:

```bash
/opt/siem-source-tracker/deploy_app.sh
```

Актуальное содержимое всегда смотрите в репозитории (`scripts/deploy_app.sh`).
Сигнатура и порядок шагов:

```text
Usage: deploy_app.sh [image_tag]   # тег — только метка (по умолчанию latest)

1. up -d postgres + ожидание pg_isready
2. pg_dump → backups/siem_source_tracker_before_<tag>_<ts>.dump
3. docker compose pull app         # тянет ngmaibulat/usiem-tracker:latest из реестра
4. docker compose run --rm migrate # идемпотентные миграции обоих планов
5. docker compose up -d            # поднять весь стек
```

Аргумент `[image_tag]` **не выбирает запускаемый образ** (стек всегда работает
на `latest`) — он лишь попадает в имя файла бэкапа и в итоговый отчёт скрипта.

Образ публичный, поэтому prod-хосту `docker login` не нужен. Tar-архивов и
каталога `releases/` больше нет — `docker load` заменен на `docker compose pull`.

Выдать права (после копирования из репозитория):

```bash
chmod +x /opt/siem-source-tracker/deploy_app.sh
```

---

## 12. Windows dev `deploy-prod.ps1`

Скрипт версионируется в этом репозитории — `deploy-prod.ps1` (запускается с
dev-машины). Build-контекст — корень репозитория приложения `siem-tracker`
(по умолчанию — соседний каталог рядом с этим репозиторием; переопределяется
параметром `-AppRepo`), скрипт сам в него переходит. Актуальное содержимое смотрите в репозитории.

Параметры и шаги:

```text
deploy-prod.ps1 [-ProdHost] [-ProdUser] [-SshKey] [-ImageTag <tag>] [-NoBuild]

Build + push (по умолчанию):
  1. docker build --no-cache -t ngmaibulat/usiem-tracker:<tag>
                             -t ngmaibulat/usiem-tracker:latest .  # контекст = корень
  2. docker push обоих тегов                                       # нужен docker login
  3. ssh sudo -n /opt/siem-source-tracker/deploy_app.sh <tag>

-NoBuild:
  пропускает build/push — prod заново подтянет текущий latest из реестра
  (redeploy). Для отката на старый тег сначала перенаправьте latest в реестре —
  см. раздел 20.
```

`-ImageTag` по умолчанию — UTC-таймстамп (`yyyyMMdd-HHmmss`). Tar-архивов, `scp`
и `releases/` больше нет: образ доставляется через `docker push` → `docker
compose pull`. Перед первым `push` выполните `docker login` под namespace
`ngmaibulat`.

---

## 13. Подготовка доработки на Windows dev

Перейти в проект:

```powershell
cd C:\path\to\siem-tracker-deploy
```

Если менялась Prisma schema (**домен** — `prisma/schema.prisma`), создать миграцию:

```powershell
pnpm.cmd exec prisma migrate dev --name <migration_name>
```

Пример:

```powershell
pnpm.cmd exec prisma migrate dev --name add_source_hold_status
```

Для control-плана (`prisma/control.prisma`) миграция создаётся так:

```powershell
pnpm.cmd run prisma:migrate:control   # prisma migrate dev --config prisma.control.config.ts
```

Чтобы применить оба плана и засеять данные одной командой (dev-БД должна быть
поднята — `docker compose up -d postgres`):

```powershell
pnpm.cmd run migrate:dev   # migrate dev (домен + control)
```

`migrate:dev` применяет миграции обоих планов. Сида админа больше нет: при первом
запуске без учётных записей приложение открывает **Мастер первоначальной настройки**
(`/setup`), где создаётся первый администратор. Демо-источников/каталога агентов
тоже нет — их заводят через UI.

Если реестр подключений (FR-31) указывает на несмигрированную схему и приложение
падает на старте, выровнять его под `DATABASE_URL` и получить рабочую БД одной
командой (пересоздаёт данные домена, идемпотентно):

```powershell
pnpm.cmd run dev:reset   # registry:reset + migrate reset --force (домен) + migrate deploy (control) + сид админа
```

Сгенерировать Prisma Client:

```powershell
pnpm.cmd exec prisma generate
```

Проверить production build локально:

```powershell
pnpm.cmd run build
```

Запустить dev-режим:

```powershell
pnpm.cmd run dev
```

Открыть:

```text
http://localhost:3000
```

Остановить dev-сервер:

```powershell
Ctrl + C
```

---

## 14. Обычный деплой с новой сборкой

Из папки проекта:

```powershell
cd C:\path\to\siem-tracker-deploy
```

Однократно (если ещё не выполнен) — логин в реестр под namespace `ngmaibulat`:

```powershell
docker login
```

Запуск (из корня этого репозитория):

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\scripts\deploy-prod.ps1 -ProdHost <prod-host> -ProdUser <prod-user> -SshKey "C:\path\to\.ssh\id_ed25519"
```

Что сделает скрипт:

```text
1. Соберет Docker image с тегами <tag> и latest (контекст = корень репо).
2. Запушит оба тега в реестр (docker push).
3. Проверит SSH-соединение.
4. Запустит удаленный deploy_app.sh <tag> (тег — метка для бэкапа/отчёта).
5. На prod будет сделан backup PostgreSQL.
6. На prod будет выполнен docker compose pull app (свежий latest из реестра).
7. Будет выполнена одноразовая миграция схемы (docker compose run --rm migrate).
8. Будет поднят стек (docker compose up -d).
```

Тег по умолчанию — UTC-таймстамп; задать явный можно через `-ImageTag <tag>`.

---

## 15. Повторный деплой уже запушенного образа

Используется, если предыдущий запуск собрал и **запушил** образ, но завис/упал
на SSH или удаленном деплое — пересобирать не нужно. Флаг `-NoBuild` пропускает
`docker build`/`docker push`; prod заново подтянет текущий `latest` из реестра:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\scripts\deploy-prod.ps1 -ProdHost <prod-host> -ProdUser <prod-user> -SshKey "C:\path\to\.ssh\id_ed25519" -NoBuild -ImageTag "20260528-175131"
```

(`-ImageTag` здесь — только метка для имени бэкапа.) Для **отката** на ранее
запушенный тег сначала перенаправьте `latest` на него в реестре, затем запустите
этот же режим — см. раздел 20.

---

## 16. Ручной деплой без PowerShell-скрипта

Если нужно обойти PowerShell-скрипт, можно выполнить шаги вручную.

Собрать и запушить образ (из корня репозитория; тег `latest` обязателен — именно
его запускает prod, версионный тег нужен для отката):

```powershell
docker build --no-cache -t ngmaibulat/usiem-tracker:20260528-175131 -t ngmaibulat/usiem-tracker:latest .
docker push ngmaibulat/usiem-tracker:20260528-175131
docker push ngmaibulat/usiem-tracker:latest
```

Запустить deploy на prod (тянет образ из реестра, без scp):

```powershell
ssh -i "C:\path\to\.ssh\id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 <prod-user>@<prod-host> "sudo -n /opt/siem-source-tracker/deploy_app.sh 20260528-175131"
```

---

## 17. Проверка после деплоя

Открыть приложение (через nginx, по HTTPS):

```text
https://<prod-host>
```

Проверить в UI:

```text
1. Приложение открывается.
2. Логин работает.
3. Дашборд отображается.
4. Источники на месте.
5. Карточки источников открываются.
6. Сохранение карточки работает.
7. Прогноз считается.
8. Экспорт отчета работает.
9. Версия приложения соответствует ожидаемой.
10. Change log открывается.
```

Проверить на prod через SSH:

```bash
ssh -i "C:\path\to\.ssh\id_ed25519" <prod-user>@<prod-host>
```

```bash
cd /opt/siem-source-tracker
docker compose ps
docker compose logs --tail=100 app
docker compose logs --tail=50 nginx
```

Проверить HTTP/HTTPS с prod-хоста (`-k` — для самоподписанного сертификата):

```bash
curl -I http://localhost            # ожидается 301 → https
curl -kI https://localhost          # ожидается ответ приложения
curl -k https://localhost/api/health  # {"status":"ok","db":true,...}
```

---

## 18. Проверка PostgreSQL

На prod:

```bash
cd /opt/siem-source-tracker
docker compose exec postgres psql -U siem -d siem_source_tracker -c "SELECT 1;"
```

Проверить количество источников:

```bash
docker compose exec postgres psql -U siem -d siem_source_tracker -c 'SELECT count(*) FROM "Source";'
```

---

## 19. Где лежат backups

Перед каждым деплоем `deploy_app.sh` создает backup:

```text
/opt/siem-source-tracker/backups/
```

Имя файла:

```text
siem_source_tracker_before_<IMAGE_TAG>_<DATE_TIME>.dump
```

Пример:

```text
siem_source_tracker_before_20260528-175131_2026-05-28_16-14-31.dump
```

Проверить:

```bash
ls -lh /opt/siem-source-tracker/backups/
```

---

## 20. Rollback приложения

Prod всегда запускает `latest`, поэтому откат = **перенаправить `latest` в
реестре на предыдущий рабочий версионный тег** (каждый деплой пушит такой тег
рядом с `latest`), после чего повторно прогнать деплой. На dev-машине,
без пересборки и без скачивания образа (манифест переписывается в реестре):

```powershell
docker buildx imagetools create -t ngmaibulat/usiem-tracker:latest ngmaibulat/usiem-tracker:<предыдущий_рабочий_тег>
```

Затем с dev-машины (сделает backup, подтянет перенаправленный `latest`,
применит миграции и поднимет стек):

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\scripts\deploy-prod.ps1 -ProdHost <prod-host> -ProdUser <prod-user> -SshKey "C:\path\to\.ssh\id_ed25519" -NoBuild -ImageTag "<предыдущий_рабочий_тег>"
```

Либо вручную на prod (после перенаправления `latest` в реестре):

```bash
cd /opt/siem-source-tracker
docker compose pull app
docker compose up -d app
```

Посмотреть, какие версионные теги уже подтянуты локально на prod:

```bash
docker images | grep usiem-tracker
```

> Откат образа не откатывает схему БД (миграции односторонние). Если новая версия
> применила миграцию, несовместимую со старым образом, откатывайте и БД — см.
> раздел 21.

Проверить:

```bash
docker compose logs --tail=100 app
curl -kI https://localhost   # приложение доступно только через nginx
```

---

## 21. Rollback БД

Откат БД выполнять только если миграция или новая версия повредила данные.

Остановить app:

```bash
cd /opt/siem-source-tracker
docker compose stop app
```

Восстановить backup:

```bash
docker compose exec -T postgres pg_restore -U siem -d siem_source_tracker --clean --if-exists < /opt/siem-source-tracker/backups/<backup_file>.dump
```

Запустить app:

```bash
docker compose up -d app
```

Проверить:

```bash
docker compose logs --tail=100 app
```

---

## 22. Диагностика зависания SSH

Если скрипт завис на шаге:

```text
Checking SSH connectivity
```

или на любой SSH-команде (в т.ч. `Running remote deploy`), проверить вручную:

```powershell
ssh -vvv -i "C:\path\to\.ssh\id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes <prod-user>@<prod-host> "echo ok"
```

Проверить доступность порта 22:

```powershell
Test-NetConnection <prod-host> -Port 22
```

Ожидаемо:

```text
TcpTestSucceeded : True
```

Проверить ping:

```powershell
ping <prod-host>
```

---

## 23. Самый короткий порядок деплоя

### Вариант A. Новый build + push + deploy

```powershell
cd C:\path\to\siem-tracker-deploy
pnpm.cmd run build   # локальная проверка сборки (опционально)
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\scripts\deploy-prod.ps1 -ProdHost <prod-host> -ProdUser <prod-user> -SshKey "C:\path\to\.ssh\id_ed25519"
```

### Вариант B. Повторить с уже запушенного тега

```powershell
cd C:\path\to\siem-tracker-deploy
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\scripts\deploy-prod.ps1 -ProdHost <prod-host> -ProdUser <prod-user> -SshKey "C:\path\to\.ssh\id_ed25519" -NoBuild -ImageTag "20260528-175131"
```

### Проверка

```text
Открыть https://<prod-host> (через nginx) и проверить приложение.
```

### Логи prod, если что-то не так

```bash
ssh <prod-user>@<prod-host>
cd /opt/siem-source-tracker
docker compose logs --tail=200 app
```
