#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/common.sh"

require_root

if [[ ! -f /etc/os-release ]]; then err 'No se puede detectar el sistema operativo.'; exit 1; fi
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) warn "Sistema detectado: ${PRETTY_NAME:-unknown}. Esta versión está preparada para Debian/Ubuntu." ;;
esac

export DEBIAN_FRONTEND=noninteractive
info "Instalando dependencias base..."
apt-get update -y
apt-get install -y bash coreutils curl wget ca-certificates procps iproute2 util-linux passwd openssh-server dropbear stunnel4 openvpn ufw python3 cron lsb-release

init_dirs
REPO_INSTALL="/opt/golbert-vpn"
install -d -m 0755 /usr/local/lib/golbert-vpn /usr/local/share/golbert-vpn "$REPO_INSTALL"
cp -a "$ROOT_DIR/lib/." /usr/local/lib/golbert-vpn/
cp -a "$ROOT_DIR/config/." /usr/local/share/golbert-vpn/
cp -a "$ROOT_DIR/." "$REPO_INSTALL/"
install -m 0755 "$ROOT_DIR/bin/golbert" /usr/local/bin/golbert

# Keep a local copy of the version and panel log directory.
install -m 0644 "$ROOT_DIR/VERSION" /etc/golbert-vpn/VERSION

# Dropbear: use port 109 unless an administrator already selected another port.
if [[ -f /etc/default/dropbear ]]; then
  sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear || true
  grep -q '^DROPBEAR_PORT=' /etc/default/dropbear || echo 'DROPBEAR_PORT=109' >> /etc/default/dropbear
  sed -i 's|^#\?DROPBEAR_BANNER=.*|DROPBEAR_BANNER="/etc/issue.net"|' /etc/default/dropbear || true
fi

cat > /etc/issue.net <<'BANNER'
=================================
      BIENVENIDO A GOLBERT VPN
=================================
Uso autorizado únicamente.
=================================
BANNER

# SSH banner without changing authentication policy.
if grep -q '^#\?Banner ' /etc/ssh/sshd_config; then
  sed -i 's|^#\?Banner .*|Banner /etc/issue.net|' /etc/ssh/sshd_config
else
  echo 'Banner /etc/issue.net' >> /etc/ssh/sshd_config
fi
sshd -t

# Enable base services. Do not overwrite custom proxy/Xray/OpenVPN configs.
systemctl enable --now ssh || systemctl enable --now sshd || true
systemctl enable --now dropbear || true
systemctl enable cron || true

# OpenVPN/Squid are installed but not forced into a server configuration.
# This prevents the installer from replacing an existing administrator config.
systemctl enable openvpn 2>/dev/null || true
systemctl enable squid 2>/dev/null || true

# Base firewall rules. UFW is enabled only after SSH/Dropbear are allowed.
ufw allow 22/tcp >/dev/null || true
ufw allow 109/tcp >/dev/null || true
ufw allow 80/tcp >/dev/null || true
ufw allow 443/tcp >/dev/null || true
ufw allow 1194/tcp >/dev/null || true
ufw allow 1194/udp >/dev/null || true
ufw allow 2200/tcp >/dev/null || true
ufw allow 2200/udp >/dev/null || true
ufw allow 3128/tcp >/dev/null || true
ufw allow 8080/tcp >/dev/null || true
ufw allow 8888/tcp >/dev/null || true
ufw allow 8181/udp >/dev/null || true
ufw allow 8282/tcp >/dev/null || true
ufw allow 8383/tcp >/dev/null || true
ufw allow 5300/udp >/dev/null || true
ufw allow 53/udp >/dev/null || true

cat > /etc/systemd/system/golbert-vpn-panel.service <<EOF2
[Unit]
Description=Golbert VPN panel environment
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload
systemctl enable golbert-vpn-panel.service >/dev/null

cat > /usr/local/bin/golbert-update <<EOF2
#!/usr/bin/env bash
set -e
cd "$REPO_INSTALL"
git pull --ff-only
exec "$REPO_INSTALL/install.sh"
EOF2
chmod +x /usr/local/bin/golbert-update

ok "Golbert VPN v$VERSION instalado."
echo
printf '%bComandos:%b\n' "$CYAN" "$RESET"
printf '  %bgolbert%b          Abrir panel\n' "$GREEN" "$RESET"
printf '  %bgolbert doctor%b  Diagnóstico\n' "$GREEN" "$RESET"
printf '  %bgolbert ports%b   Puertos escuchando\n' "$GREEN" "$RESET"
printf '  %bgolbert users%b   Usuarios\n' "$GREEN" "$RESET"
printf '  %bgolbert-update%b Actualizar desde Git\n' "$GREEN" "$RESET"
echo
warn "VLESS/VMess/Trojan/XHTTP/OHP/HCR/SlowDNS se muestran como módulos opcionales: el instalador no descarga binarios de terceros ni sobrescribe configuraciones existentes."

