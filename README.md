# GitServerZapros

> Общая инструкция по серверу и выкладке для всех проектов: https://github.com/InnVin/claude-global/blob/main/CLAUDE.md — читать первой.

Общая приёмная сигналов GitHub для всех проектов на серверах InnVin.
Коммит в рабочую ветку проекта → GitHub шлёт сигнал → **сервер в Москве** за секунды забирает изменения.

## Сервер (один, с 03.11.2026)
| Сервер | IP | Вебхук | Состояние |
|---|---|---|---|
| Москва | 195.133.10.220 | `https://dkp.195-133-10-220.sslip.io/gsz/hook` | http://195.133.10.220/status |

Все проекты и личные данные — только на этом сервере (152-ФЗ). Второго сервера сайтов нет: сервер во Франции —
только личный VPN владельца, GitServerZapros там не ставится. Страховка — GitHub, ежедневная копия данных (ниже)
и скрипты подъёма сервера с нуля — [`server/README.md`](server/README.md) (новый сервер — ~1–2 часа).
Адрес сервера берётся из паспорта `/etc/innvin/server.env` (`SERVER`, `PUBLIC_IP`, `SLUG`), в конфигах проектов IP не прописан.

## Как работает
1. GitHub (у каждого репозитория вебхук на сервер в Москве) → `/gsz/hook` на сайте `dkp.*` (сниппет `nginx-gsz.conf`).
2. `gsz-receiver` (`receiver.mjs`, порт 127.0.0.1:8095) проверяет подпись общим секретом `/etc/gsz/env`,
   находит репозиторий в `projects.json` и оставляет отметку `/var/lib/gsz/triggers/<name>`.
3. `gsz-deploy@<name>.path` видит отметку и запускает `deploy.sh <name>`: `git fetch` + fast-forward
   в папке проекта, затем команда `after` (переменные `OLD`, `NEW` — коммиты до и после).
4. Страховочный таймер `gsz-poll.timer` раз в 5 минут проверяет все проекты.
5. После каждого проекта `deploy.sh` пишет состояние (`status.mjs`): ветка, версия, дата коммита, время выкладки,
   совпадает ли с GitHub (`git ls-remote`). Страница — `http://<IP>/status`, данные — `/status.json`
   (файлы `/var/lib/gsz/www/`, адрес — `nginx-status.conf` в `/etc/nginx/projects.d/`). Текстов коммитов и секретов там нет.

## Копия данных (ежедневно на ПК владельца)
- На сервере `innvin-backup` (`server/backup.sh`, ставит `install.sh` в `/usr/local/sbin`) отдаёт в stdout архив tar.gz:
  базы SQLite FamilyTree и DKP (целостная копия `.backup`), копии DKP, данные Квартплаты и Мелочей, Автоподбор
  (отчёты, настройки, фото; без видео), LaF — база MongoDB `laf` (свежий `mongodump --archive --gzip`; если не вышел —
  последний архив `laf-backup` из `/opt/laf/backups`) и фото `/opt/laf/data/uploads`. Нет LaF или `mongodump` — шаг пропускается.
  Внутри `MANIFEST.txt` — дата, сервер, размеры, sha256 (у LaF — откуда взята база).
  Секреты не входят: `/etc`, `/opt/laf/.env`, `/opt/laf/data/secrets.json`, ключи.
- ПК владельца каждый день в 13:00 (задание Планировщика «InnVin — копия Москвы», `pc/backup-msk.ps1`) забирает архив с **Москвы**
  в `D:\YandexDisk\Yandex.Disk\Бэкапы\Сервер-Москва\innvin-ГГГГ-ММ-ДД.tar.gz`, хранит 30 последних, журнал — `backup.log` там же.
  Установка на ПК: `powershell -ExecutionPolicy Bypass -File pc\install-task.ps1` (скрипты — в `%USERPROFILE%\InnVin`).
- Восстановить: `tar -xzf innvin-ДАТА.tar.gz` → `innvin-ДАТА/var/lib/<проект>/...`; остановить службу проекта, вернуть файлы
  в `/var/lib/<проект>/` (владелец — как был), запустить службу.
- Восстановить LaF (архив — `innvin-ДАТА/opt/laf/`; `.env` и `data/secrets.json` в копию не входят — их держит сервер,
  при переезде переносятся отдельно через ПК, не печатая):
  ```bash
  systemctl stop laf
  mongorestore --uri=mongodb://127.0.0.1:27017 --archive=innvin-ДАТА/opt/laf/mongo/laf.archive.gz --gzip --drop --nsInclude='laf.*'
  rsync -a innvin-ДАТА/opt/laf/data/uploads/ /opt/laf/data/uploads/ && chown -R laf:laf /opt/laf/data/uploads
  systemctl start laf
  ```
  (`--drop` заменяет текущие коллекции базы `laf` копией; если в `/opt/laf/.env` другой `MONGO_URI` — взять адрес оттуда.)

## Добавить проект
1. Запись в `projects.json`: `"Владелец/Репо": { "name", "dir", "branch", "after" }`, при необходимости `"user"` —
   git от этого пользователя (папка принадлежит ему, как у LaF). `dir` — уже клонированная папка на сервере
   с доступом к GitHub на чтение (deploy key). Нет папки на сервере — проект пропускается («не установлен»).
2. Коммит в `main` — GitServerZapros обновит сам себя и включит слежение за новым проектом.
3. В GitHub у репозитория вебхук (адрес выше), `application/json`, событие push, секрет из `/etc/gsz/env`
   (один для всех; передавать в `gh api` с сервера через stdin, в чат не выводить).

## Установка (один раз на новый сервер)
```bash
git clone https://github.com/InnVin/GitServerZapros /opt/gsz
bash /opt/gsz/install.sh     # при переезде на новый сервер сначала положить прежний /etc/gsz/env (через ПК, не печатая) — иначе обновить секрет во всех вебхуках
```

Журнал: `journalctl -u 'gsz-*' -n 30`. В репозитории нет секретов — только код и список папок.
