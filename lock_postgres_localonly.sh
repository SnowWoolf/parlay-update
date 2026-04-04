#!/usr/bin/env bash
set -Eeuo pipefail

detect_pg_version() {
  if [[ -d /etc/postgresql ]]; then
    ls /etc/postgresql | sort -V | tail -n 1
  fi
}

log() {
  echo "[PG-LOCK] $*"
}

die() {
  echo "[PG-LOCK][ERROR] $*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  die "Скрипт должен быть запущен от root"
fi

PG_VERSION="${PG_VERSION:-$(detect_pg_version)}"
[[ -n "${PG_VERSION}" ]] || die "Не удалось определить версию PostgreSQL"

CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

[[ -f "$CONF" ]] || die "Не найден $CONF"
[[ -f "$HBA" ]] || die "Не найден $HBA"

log "Используется PostgreSQL ${PG_VERSION}"
log "Возвращаю listen_addresses = 'localhost'"
sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" "$CONF"

log "Удаляю правило host all all 0.0.0.0/0 md5"
sed -i '/^[[:space:]]*host[[:space:]]\+all[[:space:]]\+all[[:space:]]\+0\.0\.0\.0\/0[[:space:]]\+md5[[:space:]]*$/d' "$HBA"

log "Перезапускаю PostgreSQL"
systemctl restart postgresql

echo
echo "==================== POSTGRES STATUS ===================="
ss -ltnp | grep 5432 || true
echo "========================================================="
echo
echo "Текущий listen_addresses:"
grep -n "listen_addresses" "$CONF" || true
echo
echo "Проверка pg_hba.conf (не должно быть 0.0.0.0/0):"
grep -n "0.0.0.0/0" "$HBA" || true
echo
echo "PostgreSQL ограничен localhost."
