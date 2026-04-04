#!/usr/bin/env bash
set -Eeuo pipefail

PY_VER="3.10.14"
PY_MAJMIN="3.10"
PREFIX="/opt/python310"
ARCHIVE="Python-${PY_VER}.tgz"
SRC_DIR="/tmp/Python-${PY_VER}"
URL="https://www.python.org/ftp/python/${PY_VER}/${ARCHIVE}"

log() {
  echo "[PY310] $*"
}

die() {
  echo "[PY310][ERROR] $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Скрипт должен быть запущен от root"
  fi
}

install_deps() {
  log "Установка зависимостей для сборки"
  apt-get update
  apt-get install -y \
    build-essential wget curl ca-certificates pkg-config \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libffi-dev libncursesw5-dev libgdbm-dev liblzma-dev tk-dev \
    uuid-dev libexpat1-dev xz-utils
}

download_sources() {
  log "Скачивание исходников Python ${PY_VER}"
  cd /tmp
  rm -f "${ARCHIVE}"
  wget -O "${ARCHIVE}" "${URL}"
}

extract_sources() {
  log "Распаковка исходников"
  rm -rf "${SRC_DIR}"
  tar xf "/tmp/${ARCHIVE}" -C /tmp
}

build_python() {
  log "Конфигурирование Python"
  cd "${SRC_DIR}"
  ./configure --prefix="${PREFIX}"

  log "Сборка Python"
  make -j"$(nproc)"

  log "Установка Python"
  make install
}

setup_path() {
  local bashrc_target=""
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    bashrc_target="/home/${SUDO_USER}/.bashrc"
  else
    bashrc_target="/root/.bashrc"
  fi

  if [[ -f "${bashrc_target}" ]]; then
    if ! grep -q '/opt/python310/bin' "${bashrc_target}"; then
      log "Добавление /opt/python310/bin в PATH (${bashrc_target})"
      echo 'export PATH=/opt/python310/bin:$PATH' >> "${bashrc_target}"
    else
      log "PATH уже содержит /opt/python310/bin"
    fi
  fi
}

show_result() {
  echo
  echo "==================== PYTHON 3.10 STATUS ===================="
  "${PREFIX}/bin/python3.10" --version
  "${PREFIX}/bin/pip3.10" --version
  echo "============================================================"
  echo
  echo "Для текущей сессии можно сразу выполнить:"
  echo "export PATH=/opt/python310/bin:\$PATH"
}

main() {
  require_root
  install_deps
  download_sources
  extract_sources
  build_python
  setup_path
  show_result
}

main "$@"
