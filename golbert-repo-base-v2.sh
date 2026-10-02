set -e

if [[ ! -d .git ]]; then
  echo "ERROR: ejecuta este bloque dentro de la carpeta clonada golbert-vpn-v2"
  exit 1
fi

if [[ -f bin ]]; then
  rm -f bin
fi

mkdir -p bin lib config

cat > lib/common.sh <<'GOLBERT_FILE_0'
#!/usr/bin/env bash

GOLBERT_ROOT="${GOLBERT_ROOT:-/opt/golbert-vpn}"
GOLBERT_ETC="${GOLBERT_ETC:-/etc/golbert-vpn}"
GOLBERT_DATA="${GOLBERT_DATA:-/var/lib/golbert-vpn}"
GOLBERT_BACKUP_DIR="${GOLBERT_BACKUP_DIR:-/var/backups/golbert-vpn}"
GOLBERT_LOG_DIR="${GOLBERT_LOG_DIR:-/var/log/golbert-vpn}"
GOLBERT_SERVICES_FILE="${GOLBERT_SERVICES_FILE:-$GOLBERT_ETC/services.conf}"

color_enabled() { [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; }
if color_enabled; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

info()  { printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%b[ OK ]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%b[ERR ]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { error "$*"; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Este comando debe ejecutarse como root o con sudo."
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

init_dirs() {
  require_root
  install -d -m 0755 "$GOLBERT_ETC" "$GOLBERT_DATA" "$GOLBERT_BACKUP_DIR" "$GOLBERT_LOG_DIR"
}

confirm() {
  local prompt="${1:-¿Continuar?}" reply
  read -r -p "$prompt [s/N]: " reply
  [[ "$reply" =~ ^([sS]|[sS][iI])$ ]]
}

pause() {
  read -r -p "Presiona Enter para continuar..." _ || true
}

safe_name() {
  [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]
}

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

public_ip() {
  local ip=''
  if command_exists curl; then
    ip="$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
  fi
  [[ -n "$ip" ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s\n' "${ip:-desconocida}"
}

os_summary() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s %s\n' "${NAME:-Linux}" "${VERSION_ID:-}"
  else
    uname -sr
  fi
}

log_event() {
  local msg="$*"
  mkdir -p "$GOLBERT_LOG_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date '+%F %T')" "$msg" >> "$GOLBERT_LOG_DIR/golbert.log" 2>/dev/null || true
}
GOLBERT_FILE_0

cat > lib/system.sh <<'GOLBERT_FILE_1'
#!/usr/bin/env bash

system_summary() {
  echo "Sistema : $(os_summary)"
  echo "Kernel  : $(uname -r)"
  echo "Host    : $(hostname)"
  echo "IPv4    : $(public_ip)"
  echo "Uptime  : $(uptime -p 2>/dev/null || uptime)"
  echo "RAM     : $(free -h 2>/dev/null | awk '/^Mem:/ {print $3" / "$2}' || echo N/D)"
  echo "Disco / : $(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}' || echo N/D)"
}

check_dependency() {
  local cmd="$1"
  if command_exists "$cmd"; then
    printf '  %-14s OK\n' "$cmd"
    return 0
  else
    printf '  %-14s FALTA\n' "$cmd"
    return 1
  fi
}

doctor() {
  local failed=0
  echo "=== Golbert VPN Doctor ==="
  system_summary
  echo
  echo "Dependencias:"
  for cmd in bash curl ip ss systemctl awk sed grep tar; do
    check_dependency "$cmd" || failed=1
  done
  echo
  echo "Directorios:"
  for d in "$GOLBERT_ROOT" "$GOLBERT_ETC" "$GOLBERT_DATA" "$GOLBERT_BACKUP_DIR"; do
    if [[ -d "$d" ]]; then
      printf '  %-28s OK\n' "$d"
    else
      printf '  %-28s FALTA\n' "$d"
      failed=1
    fi
  done
  echo
  if [[ -f "$GOLBERT_SERVICES_FILE" ]]; then
    ok "services.conf encontrado."
  else
    warn "No existe $GOLBERT_SERVICES_FILE"
    failed=1
  fi
  if (( failed == 0 )); then
    ok "Diagnóstico básico completado sin errores."
  else
    warn "Hay elementos por corregir."
  fi
  return "$failed"
}
GOLBERT_FILE_1

cat > lib/services.sh <<'GOLBERT_FILE_2'
#!/usr/bin/env bash

service_exists() {
  systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${1}.service"
}

service_state() {
  local svc="$1"
  if ! command_exists systemctl; then
    echo "sin-systemd"
  elif ! service_exists "$svc"; then
    echo "no-instalado"
  elif systemctl is-active --quiet "$svc"; then
    echo "activo"
  elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
    echo "inactivo-habilitado"
  else
    echo "inactivo"
  fi
}

service_action() {
  require_root
  local action="$1" svc="$2"
  safe_name "$svc" || die "Nombre de servicio inválido: $svc"
  service_exists "$svc" || die "El servicio '$svc' no existe."
  case "$action" in
    start|stop|restart|reload|enable|disable|status)
      systemctl "$action" "$svc"
      ;;
    *) die "Acción no válida: $action" ;;
  esac
}

list_managed_services() {
  local line name service proto port description
  [[ -f "$GOLBERT_SERVICES_FILE" ]] || { warn "No existe $GOLBERT_SERVICES_FILE"; return 1; }
  printf '%-14s %-18s %-8s %-8s %s\n' "NOMBRE" "SERVICIO" "PROTO" "PUERTO" "ESTADO"
  printf '%-14s %-18s %-8s %-8s %s\n' "--------------" "------------------" "--------" "--------" "------------"
  while IFS='|' read -r name service proto port description; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    printf '%-14s %-18s %-8s %-8s %s\n' "$name" "$service" "$proto" "$port" "$(service_state "$service")"
  done < "$GOLBERT_SERVICES_FILE"
}

service_menu() {
  local svc action
  list_managed_services || true
  echo
  read -r -p "Servicio systemd (ej. ssh): " svc
  safe_name "$svc" || { warn "Nombre inválido."; return 1; }
  read -r -p "Acción [status/start/stop/restart/enable/disable]: " action
  service_action "$action" "$svc"
}
GOLBERT_FILE_2

cat > lib/ports.sh <<'GOLBERT_FILE_3'
#!/usr/bin/env bash

show_listeners() {
  if command_exists ss; then
    ss -tulpen
  elif command_exists netstat; then
    netstat -tulpen
  else
    die "No se encontró ss ni netstat."
  fi
}

port_in_use() {
  local port="$1" proto="${2:-tcp}"
  is_port "$port" || return 2
  if [[ "$proto" == "udp" ]]; then
    ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)${port}$"
  else
    ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
  fi
}

check_port() {
  local port="$1" proto="${2:-tcp}"
  is_port "$port" || die "Puerto inválido: $port"
  case "$proto" in tcp|udp) ;; *) die "Protocolo inválido: $proto" ;; esac
  if port_in_use "$port" "$proto"; then
    ok "$proto/$port está en escucha."
    return 0
  else
    warn "$proto/$port no está en escucha."
    return 1
  fi
}

configured_ports() {
  local name service proto port description
  [[ -f "$GOLBERT_SERVICES_FILE" ]] || { warn "No existe $GOLBERT_SERVICES_FILE"; return 1; }
  printf '%-14s %-8s %-8s %-18s %s\n' "NOMBRE" "PROTO" "PUERTO" "SERVICIO" "DESCRIPCIÓN"
  while IFS='|' read -r name service proto port description; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    printf '%-14s %-8s %-8s %-18s %s\n' "$name" "$proto" "$port" "$service" "$description"
  done < "$GOLBERT_SERVICES_FILE"
}
GOLBERT_FILE_3

cat > lib/users.sh <<'GOLBERT_FILE_4'
#!/usr/bin/env bash

list_users() {
  printf '%-20s %-8s %-22s %s\n' "USUARIO" "UID" "EXPIRA" "ESTADO"
  while IFS=: read -r user _ uid _ _ _ shell; do
    (( uid >= 1000 )) || continue
    [[ "$shell" =~ (nologin|false)$ ]] && continue
    local exp state
    exp="$(chage -l "$user" 2>/dev/null | awk -F': ' '/Account expires/ {print $2}')"
    state="$(passwd -S "$user" 2>/dev/null | awk '{print $2}')"
    printf '%-20s %-8s %-22s %s\n' "$user" "$uid" "${exp:-N/D}" "${state:-N/D}"
  done < /etc/passwd
}

create_user() {
  require_root
  local user="${1:-}" days="${2:-30}" password="${3:-}"
  [[ -n "$user" ]] || read -r -p "Nuevo usuario: " user
  safe_name "$user" || die "Usuario inválido. Usa letras, números, punto, guion o guion bajo."
  id "$user" >/dev/null 2>&1 && die "El usuario '$user' ya existe."
  [[ "$days" =~ ^[0-9]+$ ]] || die "Días inválidos."
  if [[ -z "$password" ]]; then
    read -r -s -p "Contraseña: " password; echo
    read -r -s -p "Repite contraseña: " password2; echo
    [[ "$password" == "$password2" ]] || die "Las contraseñas no coinciden."
  fi
  [[ ${#password} -ge 8 ]] || die "Usa una contraseña de al menos 8 caracteres."
  useradd -m -s /bin/bash "$user"
  printf '%s:%s\n' "$user" "$password" | chpasswd
  if (( days > 0 )); then
    chage -E "$(date -d "+${days} days" +%F)" "$user"
  fi
  log_event "Usuario creado: $user"
  ok "Usuario '$user' creado."
}

delete_user() {
  require_root
  local user="${1:-}"
  [[ -n "$user" ]] || read -r -p "Usuario a eliminar: " user
  safe_name "$user" || die "Usuario inválido."
  id "$user" >/dev/null 2>&1 || die "El usuario '$user' no existe."
  [[ "$user" != "root" ]] || die "No se puede eliminar root."
  userdel -r "$user"
  log_event "Usuario eliminado: $user"
  ok "Usuario '$user' eliminado."
}

lock_user() {
  require_root
  local user="$1"
  safe_name "$user" || die "Usuario inválido."
  passwd -l "$user"
}

unlock_user() {
  require_root
  local user="$1"
  safe_name "$user" || die "Usuario inválido."
  passwd -u "$user"
}

users_menu() {
  local op user days
  echo "1) Listar"
  echo "2) Crear"
  echo "3) Eliminar"
  echo "4) Bloquear"
  echo "5) Desbloquear"
  read -r -p "Opción: " op
  case "$op" in
    1) list_users ;;
    2) read -r -p "Usuario: " user; read -r -p "Días de vigencia [30]: " days; create_user "$user" "${days:-30}" ;;
    3) read -r -p "Usuario: " user; delete_user "$user" ;;
    4) read -r -p "Usuario: " user; lock_user "$user" ;;
    5) read -r -p "Usuario: " user; unlock_user "$user" ;;
    *) warn "Opción inválida." ;;
  esac
}
GOLBERT_FILE_4

cat > lib/firewall.sh <<'GOLBERT_FILE_5'
#!/usr/bin/env bash

firewall_status() {
  if command_exists ufw; then
    ufw status verbose
  else
    warn "UFW no está instalado."
    return 1
  fi
}

firewall_allow() {
  require_root
  local port="$1" proto="${2:-tcp}"
  is_port "$port" || die "Puerto inválido: $port"
  [[ "$proto" == tcp || "$proto" == udp ]] || die "Protocolo inválido: $proto"
  ufw allow "${port}/${proto}"
}

firewall_delete_allow() {
  require_root
  local port="$1" proto="${2:-tcp}"
  is_port "$port" || die "Puerto inválido: $port"
  ufw --force delete allow "${port}/${proto}"
}

firewall_apply_safe() {
  require_root
  command_exists ufw || die "UFW no está instalado."

  local ssh_port
  ssh_port="$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
  ssh_port="${ssh_port:-22}"

  info "Permitiendo SSH en tcp/$ssh_port antes de activar UFW..."
  ufw allow "${ssh_port}/tcp" >/dev/null

  if [[ -f "$GOLBERT_SERVICES_FILE" ]]; then
    local name service proto port description
    while IFS='|' read -r name service proto port description; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      is_port "$port" || continue
      [[ "$proto" == tcp || "$proto" == udp ]] || continue
      ufw allow "${port}/${proto}" >/dev/null || true
    done < "$GOLBERT_SERVICES_FILE"
  fi

  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw --force enable >/dev/null
  ok "UFW activado conservando el acceso SSH."
  firewall_status
}
GOLBERT_FILE_5

cat > lib/backup.sh <<'GOLBERT_FILE_6'
#!/usr/bin/env bash

create_backup() {
  require_root
  init_dirs
  local stamp out tmp
  stamp="$(date '+%Y%m%d-%H%M%S')"
  out="$GOLBERT_BACKUP_DIR/golbert-backup-$stamp.tar.gz"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/archive"
  [[ -d "$GOLBERT_ETC" ]] && cp -a "$GOLBERT_ETC" "$tmp/archive/etc-golbert-vpn"
  [[ -d /etc/ssh ]] && cp -a /etc/ssh "$tmp/archive/ssh"
  [[ -d /etc/openvpn ]] && cp -a /etc/openvpn "$tmp/archive/openvpn"
  [[ -d /etc/squid ]] && cp -a /etc/squid "$tmp/archive/squid"
  [[ -d /etc/stunnel ]] && cp -a /etc/stunnel "$tmp/archive/stunnel"
  cp -a /etc/ufw "$tmp/archive/ufw" 2>/dev/null || true

  tar -C "$tmp/archive" -czf "$out" .
  chmod 600 "$out"
  log_event "Backup creado: $out"
  ok "Backup creado: $out"
}

list_backups() {
  mkdir -p "$GOLBERT_BACKUP_DIR" 2>/dev/null || true
  find "$GOLBERT_BACKUP_DIR" -maxdepth 1 -type f -name 'golbert-backup-*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' 2>/dev/null | sort -r
}

restore_backup() {
  require_root
  local file="$1"
  [[ -f "$file" ]] || die "No existe el backup: $file"
  warn "La restauración sobrescribirá archivos de configuración incluidos en el backup."
  confirm "¿Restaurar $file?" || return 0
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  tar -xzf "$file" -C "$tmp"
  [[ -d "$tmp/etc-golbert-vpn" ]] && cp -a "$tmp/etc-golbert-vpn/." "$GOLBERT_ETC/"
  [[ -d "$tmp/ssh" ]] && cp -a "$tmp/ssh/." /etc/ssh/
  [[ -d "$tmp/openvpn" ]] && { mkdir -p /etc/openvpn; cp -a "$tmp/openvpn/." /etc/openvpn/; }
  [[ -d "$tmp/squid" ]] && { mkdir -p /etc/squid; cp -a "$tmp/squid/." /etc/squid/; }
  [[ -d "$tmp/stunnel" ]] && { mkdir -p /etc/stunnel; cp -a "$tmp/stunnel/." /etc/stunnel/; }
  [[ -d "$tmp/ufw" ]] && cp -a "$tmp/ufw/." /etc/ufw/
  ok "Backup restaurado. Revisa y reinicia los servicios necesarios."
}
GOLBERT_FILE_6

cat > lib/protocols.sh <<'GOLBERT_FILE_7'
#!/usr/bin/env bash

protocol_not_implemented() {
  local name="$1"
  warn "$name todavía no tiene backend implementado en esta versión base."
  echo "La opción está reservada para integrarla después sin romper el panel."
}

protocol_menu() {
  local op
  echo "=== Protocolos avanzados ==="
  echo " 1) VLESS"
  echo " 2) VMess"
  echo " 3) Trojan"
  echo " 4) OpenVPN"
  echo " 5) WebSocket"
  echo " 6) SlowDNS"
  echo " 7) UDP Custom"
  echo " 8) XHTTP"
  echo " 0) Volver"
  read -r -p "Opción: " op
  case "$op" in
    1) protocol_not_implemented "VLESS" ;;
    2) protocol_not_implemented "VMess" ;;
    3) protocol_not_implemented "Trojan" ;;
    4) protocol_not_implemented "OpenVPN" ;;
    5) protocol_not_implemented "WebSocket" ;;
    6) protocol_not_implemented "SlowDNS" ;;
    7) protocol_not_implemented "UDP Custom" ;;
    8) protocol_not_implemented "XHTTP" ;;
    0) return 0 ;;
    *) warn "Opción inválida." ;;
  esac
}
GOLBERT_FILE_7

cat > config/services.conf <<'GOLBERT_FILE_8'
# nombre|servicio_systemd|protocolo|puerto|descripcion
SSH|ssh|tcp|22|OpenSSH
Dropbear|dropbear|tcp|442|SSH alternativo
Stunnel|stunnel4|tcp|443|TLS wrapper
OpenVPN|openvpn|udp|1194|OpenVPN
Squid|squid|tcp|3128|Proxy HTTP
GOLBERT_FILE_8

cat > bin/golbert <<'GOLBERT_FILE_9'
#!/usr/bin/env bash
set -u

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
if [[ "$SELF" == /usr/local/bin/* && -d /opt/golbert-vpn ]]; then
  ROOT_DIR=/opt/golbert-vpn
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export GOLBERT_ROOT="${GOLBERT_ROOT:-$ROOT_DIR}"

for f in common system services ports users firewall backup protocols; do
  [[ -f "$GOLBERT_ROOT/lib/$f.sh" ]] || { echo "Falta $GOLBERT_ROOT/lib/$f.sh" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "$GOLBERT_ROOT/lib/$f.sh"
done

show_help() {
  cat <<'HELP'
Uso: golbert [comando]

Comandos:
  menu                 Abrir panel interactivo
  doctor               Diagnóstico básico
  status               Resumen de servicios gestionados
  ports                Mostrar puertos en escucha
  configured-ports     Mostrar puertos configurados
  users                Listar usuarios
  user-add [u] [dias]  Crear usuario SSH
  user-del [u]         Eliminar usuario
  firewall             Estado de UFW
  firewall-apply       Aplicar reglas seguras de UFW
  backup               Crear backup
  backups              Listar backups
  service ACCION NOMBRE  Gestionar servicio systemd
  protocols            Menú de protocolos avanzados
  system               Información del sistema
  help                  Esta ayuda
HELP
}

banner() {
  printf '%b\n' "${C_CYAN}${C_BOLD}Golbert VPN v2${C_RESET}"
  echo "Host: $(hostname) | IP: $(public_ip)"
  echo
}

main_menu() {
  local op
  while true; do
    clear 2>/dev/null || true
    banner
    echo " 1) Estado de servicios"
    echo " 2) Puertos en escucha"
    echo " 3) Puertos configurados"
    echo " 4) Usuarios SSH"
    echo " 5) Firewall"
    echo " 6) Crear backup"
    echo " 7) Listar backups"
    echo " 8) Diagnóstico"
    echo " 9) Información del sistema"
    echo "10) Protocolos avanzados"
    echo "11) Gestionar servicio"
    echo " 0) Salir"
    echo
    read -r -p "Selecciona una opción: " op
    echo
    case "$op" in
      1) list_managed_services; pause ;;
      2) show_listeners; pause ;;
      3) configured_ports; pause ;;
      4) users_menu; pause ;;
      5) firewall_status || true; echo; if confirm "¿Aplicar configuración segura de UFW?"; then firewall_apply_safe; fi; pause ;;
      6) create_backup; pause ;;
      7) list_backups; pause ;;
      8) doctor || true; pause ;;
      9) system_summary; pause ;;
      10) protocol_menu; pause ;;
      11) service_menu; pause ;;
      0) break ;;
      *) warn "Opción inválida."; sleep 1 ;;
    esac
  done
}

cmd="${1:-menu}"
case "$cmd" in
  menu) main_menu ;;
  doctor) doctor ;;
  status) list_managed_services ;;
  ports) show_listeners ;;
  configured-ports) configured_ports ;;
  users) list_users ;;
  user-add) create_user "${2:-}" "${3:-30}" ;;
  user-del) delete_user "${2:-}" ;;
  firewall) firewall_status ;;
  firewall-apply) firewall_apply_safe ;;
  backup) create_backup ;;
  backups) list_backups ;;
  service) [[ $# -ge 3 ]] || die "Uso: golbert service ACCION NOMBRE"; service_action "$2" "$3" ;;
  protocols) protocol_menu ;;
  system) system_summary ;;
  help|-h|--help) show_help ;;
  *) error "Comando desconocido: $cmd"; show_help; exit 2 ;;
esac
GOLBERT_FILE_9

cat > install.sh <<'GOLBERT_FILE_10'
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/golbert-vpn"
ETC_DIR="/etc/golbert-vpn"
BIN_LINK="/usr/local/bin/golbert"

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/common.sh"

require_root

if [[ ! -f "$ROOT_DIR/bin/golbert" ]]; then
  die "Falta $ROOT_DIR/bin/golbert"
fi
for f in common system services ports users firewall backup protocols; do
  [[ -f "$ROOT_DIR/lib/$f.sh" ]] || die "Falta $ROOT_DIR/lib/$f.sh"
done
[[ -f "$ROOT_DIR/config/services.conf" ]] || die "Falta $ROOT_DIR/config/services.conf"

info "Instalando dependencias..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y bash curl ca-certificates iproute2 openssh-server ufw tar gzip coreutils passwd

# Dependencias opcionales: se intentan instalar sin abortar toda la instalación.
for pkg in dropbear stunnel4 openvpn squid; do
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    apt-get install -y "$pkg" || warn "No se pudo instalar $pkg; puedes hacerlo manualmente después."
  fi
done

info "Copiando archivos..."
mkdir -p "$INSTALL_DIR" "$ETC_DIR"

# Evita copiar /opt/golbert-vpn sobre sí mismo cuando se actualiza desde allí.
if [[ "$(readlink -f "$ROOT_DIR")" != "$(readlink -f "$INSTALL_DIR")" ]]; then
  rm -rf "$INSTALL_DIR.new"
  mkdir -p "$INSTALL_DIR.new"
  cp -a "$ROOT_DIR/." "$INSTALL_DIR.new/"
  rm -rf "$INSTALL_DIR.old"
  if [[ -d "$INSTALL_DIR" ]]; then
    mv "$INSTALL_DIR" "$INSTALL_DIR.old"
  fi
  mv "$INSTALL_DIR.new" "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR.old"
else
  info "El instalador ya se está ejecutando desde $INSTALL_DIR; no se recopia sobre sí mismo."
fi

chmod 0755 "$INSTALL_DIR/bin/golbert"
find "$INSTALL_DIR/lib" -type f -name '*.sh' -exec chmod 0644 {} \;

if [[ ! -f "$ETC_DIR/services.conf" ]]; then
  install -m 0644 "$INSTALL_DIR/config/services.conf" "$ETC_DIR/services.conf"
else
  info "Conservando $ETC_DIR/services.conf existente."
fi

ln -sfn "$INSTALL_DIR/bin/golbert" "$BIN_LINK"
install -d -m 0755 /var/lib/golbert-vpn /var/backups/golbert-vpn /var/log/golbert-vpn

systemctl enable --now ssh >/dev/null 2>&1 || true
for svc in dropbear stunnel4 squid; do
  if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
    systemctl enable "$svc" >/dev/null 2>&1 || true
  fi
done

ok "Golbert VPN instalado."
echo
echo "Prueba estos comandos:"
echo "  golbert doctor"
echo "  golbert status"
echo "  golbert ports"
echo "  golbert"
GOLBERT_FILE_10

chmod +x install.sh bin/golbert
chmod 0644 lib/*.sh config/services.conf

for f in install.sh bin/golbert lib/*.sh; do
  bash -n "$f"
done

echo
echo "OK: archivos creados y sintaxis Bash validada."
echo
git status --short
