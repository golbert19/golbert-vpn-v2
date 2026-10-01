# Golbert VPN v2

Panel modular de administración para VPS Debian/Ubuntu. La interfaz principal está inspirada en el panel de terminal mostrado por Golbert, pero la implementación separa monitorización, servicios, usuarios, puertos, firewall y backups.

## Requisitos

- Ubuntu 22.04/24.04 LTS o Debian 11/12
- root
- systemd
- acceso a Internet para instalar paquetes APT

## Instalación

```bash
git clone https://github.com/golbert19/golbert-vpn.git
cd golbert-vpn
chmod +x install.sh bin/golbert
./install.sh
golbert
```

Si vas a probar esta v2 en una rama nueva, sustituye la URL por tu repositorio/branch.

## Comandos

```bash
golbert
golbert doctor
golbert ports
golbert users
golbert backup
golbert service status ssh
golbert service restart dropbear
golbert-update
```

## Estructura

```text
golbert-vpn/
├── install.sh
├── VERSION
├── README.md
├── .gitignore
├── bin/
│   └── golbert
├── lib/
│   ├── common.sh
│   ├── system.sh
│   ├── services.sh
│   ├── ports.sh
│   ├── users.sh
│   ├── firewall.sh
│   ├── backup.sh
│   └── protocols.sh
├── config/
│   ├── services.conf
│   ├── xray.example.json
│   └── openvpn-server.example.conf
├── systemd/
└── docs/
    └── protocols.md
```

## Seguridad

El instalador no hace `apt upgrade` completo, no abre automáticamente UDP 1-65535 y no sobrescribe configuraciones de OpenVPN/Xray existentes. Haz una copia de seguridad antes de migrar un VPS de producción.

## Licencia

MIT. Ajusta el archivo LICENSE si quieres conservar la licencia de tu repositorio original.
