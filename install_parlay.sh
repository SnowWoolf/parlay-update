#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/Parlay"
REPO_URL="https://github.com/s-nosonov-chernomor/Parlay.git"
SERVICE_FILE="/etc/systemd/system/parlay.service"
PYTHON_BIN="/opt/python310/bin/python3.10"
VENV_DIR="$APP_DIR/venv"
ENV_FILE="$APP_DIR/.env"

TMP_BUILD_DIR="/opt/tmp"
PG_VERSION="12"

log() {
  echo "[PARLAY] $*"
}

die() {
  echo "[PARLAY][ERROR] $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Скрипт должен быть запущен от root"
  fi
}

detect_pg_version() {
  if [[ -d /etc/postgresql ]]; then
    local first_ver
    first_ver="$(ls /etc/postgresql | sort -V | tail -n 1 || true)"
    if [[ -n "${first_ver}" ]]; then
      PG_VERSION="${first_ver}"
    fi
  fi
}

install_system_packages() {
  log "Установка системных пакетов"
  apt update
  apt install -y \
    git \
    build-essential \
    libpq-dev \
    postgresql \
    postgresql-client \
    python3-dev \
    libffi-dev \
    rustc \
    cargo
}

ensure_python() {
  [[ -x "$PYTHON_BIN" ]] || die "Не найден Python: $PYTHON_BIN"
}

clone_or_update_repo() {
  if [[ -d "$APP_DIR/.git" ]]; then
    log "Обнаружен существующий Parlay, обновляю репозиторий"
    systemctl stop parlay 2>/dev/null || true
    pkill -f 'uvicorn app.main:app' 2>/dev/null || true

    cd "$APP_DIR"
    git fetch --all --prune --tags
    git reset --hard origin/master
    git rev-parse HEAD
    git log --oneline -n 1
  else
    log "Клонирование репозитория"
    mkdir -p /opt
    git clone "$REPO_URL" "$APP_DIR"
  fi
}

ensure_venv() {
  if [[ ! -d "$VENV_DIR" ]]; then
    log "Создание venv"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi

  # shellcheck disable=SC1090
  . "$VENV_DIR/bin/activate"

  log "Обновление pip/setuptools/wheel"
  python -m pip install --upgrade pip wheel
  python -m pip install "setuptools<81" setuptools-rust
}

install_python_deps() {
  # shellcheck disable=SC1090
  . "$VENV_DIR/bin/activate"

  log "Установка Python-зависимостей"
  pip install uvicorn psycopg

  pip install \
    fastapi \
    pydantic \
    pydantic-settings \
    sqlalchemy \
    alembic \
    paho-mqtt \
    orjson \
    python-dotenv \
    prometheus-client \
    openpyxl \
    itsdangerous \
    passlib

  log "Установка bcrypt 4.0.1"
  mkdir -p "$TMP_BUILD_DIR"
  export TMPDIR="$TMP_BUILD_DIR"
  export CARGO_TARGET_DIR="$TMP_BUILD_DIR/cargo-target"

  pip install --no-build-isolation --no-cache-dir bcrypt==4.0.1

  python -c "import bcrypt; print(bcrypt.__version__)" >/dev/null || die "bcrypt установлен некорректно"
}

create_env_if_missing() {
  if [[ -f "$ENV_FILE" ]]; then
    log ".env уже существует, не изменяю"
    return
  fi

  log "Создание .env"
  cat > "$ENV_FILE" <<'EOF'
APP_NAME=parlay
ENV=prod

HTTP_HOST=0.0.0.0
HTTP_PORT=8000

DB_URL=postgresql+psycopg://parlay:parlay123@127.0.0.1:5432/parlay

MQTT_HOST=127.0.0.1
MQTT_PORT=1883
MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_CLIENT_ID=parlay-1
MQTT_SUBSCRIBE=#
MQTT_QOS=1
MQTT_KEEPALIVE=60

INGEST_QUEUE_MAX=50000
DB_BATCH_SIZE=500
DB_FLUSH_INTERVAL_MS=250
PARAM_CACHE_SIZE=200000

STORE_RAW=true
API_TOKEN=change-me

HEALTH_STALE_S=120
HEALTH_SILENT_WARN_S=30
HEALTH_SILENT_CRIT_S=120
HEALTH_INCLUDE_MANUAL_TOPIC=true
EOF
}

ensure_postgres_running() {
  log "Проверка PostgreSQL"
  systemctl enable postgresql
  systemctl restart postgresql
  detect_pg_version
}

ensure_db_role_and_db() {
  log "Создание роли и БД (если отсутствуют)"
  sudo -u postgres psql -d postgres -c "CREATE ROLE parlay LOGIN PASSWORD 'parlay123';" || true
  sudo -u postgres psql -d postgres -c "CREATE DATABASE parlay OWNER parlay;" || true
  sudo -u postgres psql -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE parlay TO parlay;"
}

open_postgres_temporarily() {
  local conf="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
  local hba="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

  [[ -f "$conf" ]] || die "Не найден $conf"
  [[ -f "$hba" ]] || die "Не найден $hba"

  log "Временное открытие PostgreSQL для восстановления БД"
  sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "$conf"

  if ! grep -q 'host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+0\.0\.0\.0/0[[:space:]]\+md5' "$hba"; then
    echo "host    all    all    0.0.0.0/0    md5" >> "$hba"
  fi

  systemctl restart postgresql
}

ensure_systemd_service() {
  log "Создание/обновление systemd unit"
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=PARLAY
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/Parlay
ExecStart=/opt/Parlay/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable parlay
}

start_service() {
  log "Запуск Parlay"
  systemctl restart parlay
}

show_result() {
  echo
  echo "==================== PARLAY STATUS ===================="
  systemctl status parlay --no-pager -l || true
  echo "======================================================="
  echo
  echo "НЕОБХОДИМО РАЗВЕРНУТЬ БАЗУ ДАННЫХ! После восстановленя БД не забудь настроить безопасность!"
  echo
  echo "Для восстановления БД с Windows:"
  echo "\"C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe\" -h <IP_УСТРОЙСТВА> -U parlay -d parlay --no-owner --role=parlay <backup_file>"
  echo
}

main() {
  require_root
  install_system_packages
  ensure_python
  clone_or_update_repo
  ensure_venv
  install_python_deps
  create_env_if_missing
  ensure_postgres_running
  ensure_db_role_and_db
  open_postgres_temporarily
  ensure_systemd_service
  start_service
  show_result
}

main "$@"
