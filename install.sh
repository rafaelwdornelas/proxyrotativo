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

echo "👤 Usuário: $REAL_USER"
echo "📁 Home: $USER_HOME"
echo ""

# Verificar se os arquivos necessários existem
echo "🔍 Verificando arquivos necessários..."
MISSING_FILES=0

if [ ! -f "proxy-manager.sh" ]; then
    echo "  ❌ proxy-manager.sh não encontrado"
    MISSING_FILES=1
fi

if [ ! -f "proxy-api/main.go" ]; then
    echo "  ❌ proxy-api/main.go não encontrado"
    MISSING_FILES=1
fi

if [ ! -d "systemd" ]; then
    echo "  ❌ Pasta systemd/ não encontrada"
    MISSING_FILES=1
fi

if [ $MISSING_FILES -eq 1 ]; then
    echo ""
    echo "❌ Arquivos necessários não encontrados!"
    echo "Execute este script na raiz do repositório clonado."
    exit 1
fi

echo "  ✅ Todos os arquivos encontrados"
echo ""

# Perguntar se quer continuar
read -p "Deseja continuar com a instalação? (s/N) " -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Instalação cancelada."
    exit 0
fi

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

# Voltar para o diretório do script
cd - > /dev/null

echo ""
echo "📄 Copiando arquivos do projeto..."

# Copiar proxy-manager.sh
cp proxy-manager.sh $USER_HOME/proxy-system/
chmod +x $USER_HOME/proxy-system/proxy-manager.sh
echo "  ✓ proxy-manager.sh copiado"

# Copiar main.go
cp proxy-api/main.go $USER_HOME/proxy-api/
echo "  ✓ main.go copiado"

# Ajustar permissões
chown -R $REAL_USER:$REAL_USER $USER_HOME/proxy-system
chown -R $REAL_USER:$REAL_USER $USER_HOME/proxy-api

echo ""
echo "📦 Compilando API Go..."
cd $USER_HOME/proxy-api

# Compilar como o usuário real
if su - $REAL_USER -c "cd $USER_HOME/proxy-api && go build -o proxy-api main.go" 2>&1; then
    chmod +x $USER_HOME/proxy-api/proxy-api
    echo "  ✅ API compilada com sucesso"
else
    echo "  ❌ Erro ao compilar API. Você precisará compilar manualmente depois."
fi

cd - > /dev/null

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
echo "⚙️  Configurando systemd services..."

# Criar proxy-api.service
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

echo "  ✓ proxy-api.service criado"

# Criar proxy-system.service
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

echo "  ✓ proxy-system.service criado"

# Recarregar systemd
systemctl daemon-reload

echo ""
echo "🔧 Habilitando IP forwarding permanente..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p > /dev/null 2>&1

echo ""
echo "✅ Verificando instalação..."
echo -n "  ModemManager: "
systemctl is-active ModemManager && echo "✓" || echo "✗"

echo -n "  3proxy: "
/usr/local/bin/3proxy --version > /dev/null 2>&1 && echo "✓" || echo "✗"

echo -n "  Go: "
go version > /dev/null 2>&1 && echo "✓" || echo "✗"

echo -n "  API compilada: "
[ -f "$USER_HOME/proxy-api/proxy-api" ] && echo "✓" || echo "✗"

echo ""
echo "========================================="
echo "✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "========================================="
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1. CONFIGURAR APN (se necessário):"
echo "   nano $USER_HOME/proxy-system/proxy-manager.sh"
echo "   (Edite as variáveis APN, USER e PASS no início do arquivo)"
echo ""
echo "2. INICIAR SISTEMA:"
echo "   sudo $USER_HOME/proxy-system/proxy-manager.sh start"
echo ""
echo "3. INICIAR API:"
echo "   sudo systemctl start proxy-api"
echo "   sudo systemctl enable proxy-api"
echo ""
echo "4. HABILITAR INICIALIZAÇÃO AUTOMÁTICA:"
echo "   sudo systemctl enable proxy-system"
echo ""
echo "5. ACESSAR DASHBOARD:"
echo "   http://SEU_IP:5000"
echo ""
echo "========================================="
echo "📊 Comandos úteis:"
echo ""
echo "  Ver status API:"
echo "    sudo systemctl status proxy-api"
echo ""
echo "  Ver logs API:"
echo "    sudo journalctl -u proxy-api -f"
echo ""
echo "  Ver status sistema:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh status"
echo ""
echo "  Renovar IP de porta:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh renew-port 6001"
echo ""
echo "  Reiniciar sistema completo:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh restart"
echo ""
echo "========================================="
echo "🔗 Modems detectados:"
mmcli -L 2>/dev/null || echo "  Nenhum modem detectado. Conecte os modems USB e reinicie o ModemManager."
echo ""
echo "========================================="
echo "✨ Instalação finalizada!"
echo "========================================="