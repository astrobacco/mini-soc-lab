#!/usr/bin/env bash
# soc VM: the analyst tools, both running as Docker containers
#   - Greenbone Community Edition (OpenVAS)  -> vulnerability scanning
#   - DFIR-IRIS                              -> alerts, cases, incident response
set -euo pipefail
source /opt/minisoc/lib.sh
FILES=/tmp/minisoc-soc

# ---------------------------------------------------------------- docker
if ! command -v docker >/dev/null; then
    log "Installing Docker"
    apt_install docker.io docker-compose-v2 git
    usermod -aG docker vagrant
fi
systemctl enable --now docker >/dev/null

# ---------------------------------------------------------------- DFIR-IRIS
IRIS_DIR=/opt/iris-web
if [ ! -d "$IRIS_DIR" ]; then
    log "Downloading DFIR-IRIS ${IRIS_VERSION}"
    git clone -q --depth 1 -b "${IRIS_VERSION}" https://github.com/dfir-iris/iris-web.git "$IRIS_DIR"
fi
log "Configuring DFIR-IRIS"
cp "${IRIS_DIR}/.env.model" "${IRIS_DIR}/.env"
set_env() { sed -i "s|^#\{0,1\}\s*$1=.*|$1=$2|" "${IRIS_DIR}/.env"; grep -q "^$1=" "${IRIS_DIR}/.env" || echo "$1=$2" >> "${IRIS_DIR}/.env"; }
set_env SERVER_NAME                 soc.minisoc.lab
set_env POSTGRES_PASSWORD           "${IRIS_DB_PASSWORD}"
set_env POSTGRES_ADMIN_PASSWORD     "${IRIS_DB_ADMIN_PASSWORD}"
set_env IRIS_SECRET_KEY             "${IRIS_SECRET_KEY}"
set_env IRIS_SECURITY_PASSWORD_SALT "${IRIS_PASSWORD_SALT}"
set_env IRIS_ADM_USERNAME           administrator
set_env IRIS_ADM_EMAIL              administrator@minisoc.lab
set_env IRIS_ADM_PASSWORD           "${LAB_PASSWORD}"
set_env IRIS_ADM_API_KEY            "${IRIS_API_KEY}"
chmod 600 "${IRIS_DIR}/.env"

log "Starting DFIR-IRIS (first start downloads ~1.5 GB of images)"
( cd "$IRIS_DIR" && docker compose pull -q && docker compose up -d --quiet-pull ) >/dev/null
wait_for "DFIR-IRIS web interface" 600 curl -sfk -o /dev/null https://127.0.0.1/login
wait_for "DFIR-IRIS API key" 120 curl -sfk -H "Authorization: Bearer ${IRIS_API_KEY}" https://127.0.0.1/api/ping

# ---------------------------------------------------------------- Greenbone
GB_DIR=/opt/greenbone
mkdir -p "$GB_DIR"
if [ ! -f "${GB_DIR}/docker-compose.yml" ]; then
    log "Downloading Greenbone Community Edition"
    curl -fsSL -o "${GB_DIR}/docker-compose.yml" https://greenbone.github.io/docs/latest/_static/docker-compose.yml
    # IRIS already uses 443 on this VM: publish the Greenbone web UI on 9392 only,
    # on all interfaces so it can be reached from the host (via port forward).
    sed -i -e '/- 127.0.0.1:443:443/d' -e 's|- 127.0.0.1:9392:9392|- 9392:9392|' "${GB_DIR}/docker-compose.yml"
fi
log "Starting Greenbone (downloads ~3 GB of images; vulnerability feeds keep syncing for ~30-60 min afterwards)"
( cd "$GB_DIR" && docker compose pull -q && docker compose up -d --quiet-pull ) >/dev/null

log "Waiting for the Greenbone manager (gvmd)"
wait_for "gvmd" 900 bash -c "cd ${GB_DIR} && docker compose exec -T -u gvmd gvmd gvmd --get-users | grep -qx admin"
( cd "$GB_DIR" && docker compose exec -T -u gvmd gvmd gvmd --user=admin --new-password="${LAB_PASSWORD}" )
wait_for "Greenbone web interface" 300 curl -sfk -o /dev/null https://127.0.0.1:9392/

# ---------------------------------------------------------------- helpers
install -m 755 "${FILES}/greenbone-setup-scan.sh" /opt/minisoc/greenbone-setup-scan.sh
install -m 600 /dev/null /opt/minisoc/greenbone.env
echo "LAB_PASSWORD=${LAB_PASSWORD}" > /opt/minisoc/greenbone.env
install -m 644 "${FILES}/minisoc-greenbone-scan.service" /etc/systemd/system/minisoc-greenbone-scan.service
systemctl daemon-reload
# Runs once in the background: waits until the feeds are loaded, then
# creates the "Mini-SOC SERVERS" target + scan task in Greenbone.
systemctl enable --now --no-block minisoc-greenbone-scan.service >/dev/null

rm -rf "${FILES}"
log "DFIR-IRIS: https://localhost:${PORT_IRIS:-8445}       (user: administrator)"
log "Greenbone: https://localhost:${PORT_GREENBONE:-9392}  (user: admin)"
