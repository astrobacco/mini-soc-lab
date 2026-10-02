# Shared helpers for the provisioning scripts (source this file).
export DEBIAN_FRONTEND=noninteractive

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(hostname -s)" "$*"; }
die() { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(hostname -s)" "$*" >&2; exit 1; }

# apt with retries (mirrors and the network are not always reliable)
apt_install() {
    local i
    for i in 1 2 3; do
        apt-get -qq update && apt-get -qq -y -o Dpkg::Options::=--force-confold install "$@" >/dev/null && return 0
        log "apt failed (attempt $i), retrying in 10s"; sleep 10
    done
    die "could not install: $*"
}

# wait_for <description> <seconds> <command...>
wait_for() {
    local what=$1 timeout=$2; shift 2
    local start=$SECONDS
    until "$@" >/dev/null 2>&1; do
        (( SECONDS - start > timeout )) && die "timed out waiting for ${what}"
        sleep 5
    done
}

install_wazuh_agent() {
    local group=$1
    if ! dpkg -s wazuh-agent >/dev/null 2>&1; then
        log "Installing Wazuh agent ${WAZUH_VERSION} (group: ${group})"
        curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor --yes -o /usr/share/keyrings/wazuh.gpg
        echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
        WAZUH_MANAGER="${WAZUH_MANAGER}" WAZUH_AGENT_GROUP="${group}" WAZUH_AGENT_NAME="$(hostname -s)" \
            apt_install "wazuh-agent=${WAZUH_VERSION}-1"
        # keep the agent at the same version as the manager
        apt-mark hold wazuh-agent >/dev/null
    fi
    systemctl daemon-reload
    systemctl enable --now wazuh-agent >/dev/null
}
