#!/bin/bash
# Instalação Automática Completa - Sistema Multi-Modem Proxy
# Execução: sudo bash install.sh

set -e

echo "========================================="
echo "🚀 INSTALAÇÃO DO SISTEMA MULTI-MODEM"
echo "========================================="
echo ""

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Execute como root: sudo bash install.sh"
    exit 1
fi

# Obter usuário real (não root)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)

echo "📦 Atualizando sistema..."
apt update && apt upgrade -y

echo ""
echo "📦 Instalando dependências..."
apt install -y \
    modemmanager \
    network-manager \
    libqmi-utils \
    libmbim-utils \
    usb-modeswitch \
    build-essential \
    git \
    curl \
    wget \
    net-tools \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    ufw \
    golang-go \
    jq

echo ""
echo "🔧 Habilitando ModemManager..."
systemctl enable ModemManager
systemctl start ModemManager

echo ""
echo "📥 Instalando 3proxy..."
cd /tmp
if [ ! -d "3proxy-0.9.4" ]; then
    wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
    tar -xzf 0.9.4.tar.gz
fi

cd 3proxy-0.9.4
make -f Makefile.Linux

mkdir -p /usr/local/bin
mkdir -p /etc/3proxy
mkdir -p /var/log/3proxy

cp bin/3proxy /usr/local/bin/
chmod +x /usr/local/bin/3proxy

echo ""
echo "📂 Criando estrutura de diretórios..."
mkdir -p $USER_HOME/proxy-system
mkdir -p $USER_HOME/proxy-system/logs
mkdir -p $USER_HOME/proxy-api

chown -R $REAL_USER:$REAL_USER $USER_HOME/proxy-system
chown -R $REAL_USER:$REAL_USER $USER_HOME/proxy-api

echo ""
echo "🔐 Configurando permissões sudo..."
cat > /etc/sudoers.d/proxy-manager << EOF
# Permissões para proxy-manager e API
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/mmcli
$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/ip
$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/iptables
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/killall
$REAL_USER ALL=(ALL) NOPASSWD: /usr/local/bin/3proxy
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/pgrep
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/netstat
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/uptime
$REAL_USER ALL=(ALL) NOPASSWD: $USER_HOME/proxy-system/proxy-manager.sh
EOF

chmod 440 /etc/sudoers.d/proxy-manager

echo ""
echo "🔥 Configurando firewall..."
ufw --force enable
ufw allow 22/tcp
ufw allow 5000/tcp
ufw allow 6001:6010/tcp
ufw allow 6101:6110/tcp
ufw reload

echo ""
echo "⚙️  Configurando systemd service para API..."
cat > /etc/systemd/system/proxy-api.service << EOF
[Unit]
Description=Proxy Manager API
After=network.target ModemManager.service

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$USER_HOME/proxy-api
ExecStart=$USER_HOME/proxy-api/proxy-api
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "⚙️  Configurando systemd service para inicialização automática..."
cat > /etc/systemd/system/proxy-system.service << EOF
[Unit]
Description=Proxy Multi-Modem System
After=network.target ModemManager.service
Requires=ModemManager.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/bin/sudo -u root $USER_HOME/proxy-system/proxy-manager.sh start
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "🔧 Habilitando IP forwarding permanente..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

echo ""
echo "✅ Verificando instalação..."
echo -n "  ModemManager: "
systemctl is-active ModemManager && echo "✓" || echo "✗"

echo -n "  3proxy: "
/usr/local/bin/3proxy --version > /dev/null 2>&1 && echo "✓" || echo "✗"

echo -n "  Go: "
go version | grep -q "go version" && echo "✓" || echo "✗"

echo ""
echo "========================================="
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "========================================="
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1. Cole o arquivo proxy-manager.sh em $USER_HOME/proxy-system/"
echo "   chmod +x $USER_HOME/proxy-system/proxy-manager.sh"
echo ""
echo "2. Cole o arquivo main.go em $USER_HOME/proxy-api/"
echo ""
echo "3. Compile a API:"
echo "   cd $USER_HOME/proxy-api"
echo "   go build -o proxy-api main.go"
echo ""
echo "4. INICIAR SISTEMA (primeira vez):"
echo "   sudo $USER_HOME/proxy-system/proxy-manager.sh start"
echo ""
echo "5. INICIAR API:"
echo "   sudo systemctl start proxy-api"
echo "   sudo systemctl enable proxy-api"
echo ""
echo "6. HABILITAR INICIALIZAÇÃO AUTOMÁTICA:"
echo "   sudo systemctl enable proxy-system"
echo ""
echo "📊 Comandos úteis:"
echo "  - Ver status: sudo systemctl status proxy-api"
echo "  - Ver logs API: sudo journalctl -u proxy-api -f"
echo "  - Ver logs sistema: tail -f $USER_HOME/proxy-system/logs/*.log"
echo "  - Dashboard: http://SEU_IP:5000"
echo ""
echo "🔗 Modems detectados:"
mmcli -L
echo ""
echo "========================================="