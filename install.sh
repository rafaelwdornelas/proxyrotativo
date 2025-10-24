#!/bin/bash
# Instalação Automática Completa - Sistema Multi-Modem Proxy
# Versão: 2.1 - Com detecção automática de diretório
# Execução: sudo bash install.sh

set -e

# ============================================================================
# DETECTAR DIRETÓRIO DO SCRIPT AUTOMATICAMENTE
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "🚀 INSTALAÇÃO DO SISTEMA MULTI-MODEM"
echo "       Versão 2.1"
echo "========================================="
echo ""
echo "📂 Diretório detectado: $SCRIPT_DIR"
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

# Mudar para o diretório do script
cd "$SCRIPT_DIR"

# Verificar se os arquivos necessários existem
echo "🔍 Verificando arquivos necessários..."
MISSING_FILES=0

if [ ! -f "$SCRIPT_DIR/proxy-manager.sh" ]; then
    echo "  ❌ proxy-manager.sh não encontrado em: $SCRIPT_DIR/proxy-manager.sh"
    MISSING_FILES=1
else
    echo "  ✓ proxy-manager.sh encontrado"
fi

if [ ! -f "$SCRIPT_DIR/proxy-api/main.go" ]; then
    echo "  ❌ proxy-api/main.go não encontrado em: $SCRIPT_DIR/proxy-api/main.go"
    MISSING_FILES=1
else
    echo "  ✓ proxy-api/main.go encontrado"
fi

if [ $MISSING_FILES -eq 1 ]; then
    echo ""
    echo "❌ Arquivos necessários não encontrados!"
    echo ""
    echo "Estrutura esperada:"
    echo "  $SCRIPT_DIR/"
    echo "  ├── install.sh"
    echo "  ├── proxy-manager.sh"
    echo "  └── proxy-api/"
    echo "      └── main.go"
    echo ""
    echo "Certifique-se de que os arquivos estão no mesmo diretório do install.sh"
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

echo ""
echo "========================================="
echo "🔄 ATUALIZANDO SISTEMA OPERACIONAL"
echo "========================================="
echo ""
echo "⏳ Isso pode demorar alguns minutos..."
echo ""

# Atualizar lista de pacotes
echo "📦 Atualizando lista de pacotes..."
apt update

# Atualizar pacotes instalados
echo ""
echo "⬆️  Atualizando pacotes do sistema..."
DEBIAN_FRONTEND=noninteractive apt upgrade -y

# Atualizar pacotes com dependências quebradas (dist-upgrade)
echo ""
echo "🔧 Realizando atualização completa (dist-upgrade)..."
DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y

# Limpar pacotes desnecessários
echo ""
echo "🧹 Removendo pacotes desnecessários..."
apt autoremove -y
apt autoclean

echo ""
echo "✅ Sistema operacional atualizado com sucesso!"
echo ""

sleep 2

echo "========================================="
echo "📦 INSTALANDO DEPENDÊNCIAS"
echo "========================================="
echo ""

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
    golang-go \
    jq

echo ""
echo "🔧 Habilitando ModemManager..."
systemctl enable ModemManager
systemctl start ModemManager

echo ""
echo "========================================="
echo "📥 INSTALANDO 3PROXY"
echo "========================================="
echo ""

cd /tmp
if [ ! -d "3proxy-0.9.4" ]; then
    echo "Baixando 3proxy 0.9.4..."
    wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
    tar -xzf 0.9.4.tar.gz
else
    echo "3proxy já baixado, pulando download..."
fi

cd 3proxy-0.9.4
echo "Compilando 3proxy..."
make -f Makefile.Linux

echo "Instalando 3proxy..."
mkdir -p /usr/local/bin
mkdir -p /etc/3proxy
mkdir -p /var/log/3proxy

cp bin/3proxy /usr/local/bin/
chmod +x /usr/local/bin/3proxy

echo "✅ 3proxy instalado com sucesso!"

# Voltar para o diretório do script
cd "$SCRIPT_DIR"

echo ""
echo "========================================="
echo "📂 CRIANDO ESTRUTURA DE DIRETÓRIOS"
echo "========================================="
echo ""

mkdir -p "$USER_HOME/proxy-system"
mkdir -p "$USER_HOME/proxy-system/logs"
mkdir -p "$USER_HOME/proxy-api"

echo "  ✓ Diretórios criados em $USER_HOME"

echo ""
echo "========================================="
echo "📄 COPIANDO ARQUIVOS DO PROJETO"
echo "========================================="
echo ""

# Copiar proxy-manager.sh
echo "Copiando proxy-manager.sh..."
echo "  De: $SCRIPT_DIR/proxy-manager.sh"
echo "  Para: $USER_HOME/proxy-system/proxy-manager.sh"
cp "$SCRIPT_DIR/proxy-manager.sh" "$USER_HOME/proxy-system/"
chmod +x "$USER_HOME/proxy-system/proxy-manager.sh"
echo "  ✓ proxy-manager.sh copiado"

# Copiar main.go
echo ""
echo "Copiando main.go..."
echo "  De: $SCRIPT_DIR/proxy-api/main.go"
echo "  Para: $USER_HOME/proxy-api/main.go"
cp "$SCRIPT_DIR/proxy-api/main.go" "$USER_HOME/proxy-api/"
echo "  ✓ main.go copiado"

# Ajustar permissões
chown -R $REAL_USER:$REAL_USER "$USER_HOME/proxy-system"
chown -R $REAL_USER:$REAL_USER "$USER_HOME/proxy-api"
echo "  ✓ Permissões ajustadas"

echo ""
echo "========================================="
echo "📦 COMPILANDO API GO"
echo "========================================="
echo ""

cd "$USER_HOME/proxy-api"

# Compilar como o usuário real
echo "Compilando proxy-api..."
if su - $REAL_USER -c "cd $USER_HOME/proxy-api && go build -o proxy-api main.go" 2>&1; then
    chmod +x "$USER_HOME/proxy-api/proxy-api"
    echo "  ✅ API compilada com sucesso"
else
    echo "  ❌ Erro ao compilar API. Você precisará compilar manualmente depois."
    echo "     cd ~/proxy-api && go build -o proxy-api main.go"
fi

# Voltar para o diretório do script
cd "$SCRIPT_DIR"

echo ""
echo "========================================="
echo "🔐 CONFIGURANDO PERMISSÕES SUDO"
echo "========================================="
echo ""

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
echo "✅ Permissões sudo configuradas"

echo ""
echo "========================================="
echo "🔥 DESABILITANDO FIREWALL COMPLETAMENTE"
echo "========================================="
echo ""

# Parar e desabilitar UFW
echo "Desabilitando UFW..."
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
ufw disable 2>/dev/null || true
echo "  ✓ UFW desabilitado"

# Parar e desabilitar firewalld (caso esteja instalado)
echo "Desabilitando firewalld..."
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
echo "  ✓ firewalld desabilitado"

# Limpar todas as regras do iptables
echo "Limpando regras iptables..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
echo "  ✓ Todas as regras iptables removidas"

# Desinstalar iptables-persistent se existir
echo "Removendo iptables-persistent..."
apt-get remove --purge -y iptables-persistent 2>/dev/null || true
apt-get remove --purge -y netfilter-persistent 2>/dev/null || true
echo "  ✓ iptables-persistent removido"

# Garantir que não há scripts de firewall no boot
systemctl disable iptables 2>/dev/null || true
systemctl stop iptables 2>/dev/null || true
echo "  ✓ Serviço iptables desabilitado"

echo ""
echo "✅ Firewall completamente desabilitado!"

echo ""
echo "========================================="
echo "⚙️  CONFIGURANDO SYSTEMD SERVICES"
echo "========================================="
echo ""

# Criar proxy-api.service
cat > /etc/systemd/system/proxy-api.service << EOF
[Unit]
Description=Proxy Manager API v2.0
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
Description=Proxy Multi-Modem System v2.0
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
echo "  ✓ systemd recarregado"

echo ""
echo "========================================="
echo "🔧 HABILITANDO IP FORWARDING"
echo "========================================="
echo ""

if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p > /dev/null 2>&1
echo "✅ IP forwarding habilitado permanentemente"

echo ""
echo "========================================="
echo "✅ VERIFICANDO INSTALAÇÃO"
echo "========================================="
echo ""

echo -n "  ModemManager: "
systemctl is-active ModemManager >/dev/null 2>&1 && echo "✓ RODANDO" || echo "✗ PARADO"

echo -n "  3proxy: "
/usr/local/bin/3proxy --version > /dev/null 2>&1 && echo "✓ INSTALADO" || echo "✗ NÃO INSTALADO"

echo -n "  Go: "
go version > /dev/null 2>&1 && echo "✓ INSTALADO" || echo "✗ NÃO INSTALADO"

echo -n "  API compilada: "
[ -f "$USER_HOME/proxy-api/proxy-api" ] && echo "✓ OK" || echo "✗ FALTANDO"

echo -n "  proxy-manager.sh: "
[ -f "$USER_HOME/proxy-system/proxy-manager.sh" ] && echo "✓ OK" || echo "✗ FALTANDO"

echo -n "  Firewall: "
if systemctl is-active ufw >/dev/null 2>&1 || systemctl is-active firewalld >/dev/null 2>&1; then
    echo "⚠️  ATIVO (verificar manualmente)"
else
    echo "✓ DESABILITADO"
fi

echo ""
echo "========================================="
echo "✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "========================================="
echo ""
echo "⚠️  ATENÇÃO: FIREWALL COMPLETAMENTE DESABILITADO"
echo "   Use apenas em ambiente local/controlado!"
echo ""
echo "📋 PRÓXIMOS PASSOS:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  CONFIGURAR APN (se necessário):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   nano $USER_HOME/proxy-system/proxy-manager.sh"
echo ""
echo "   Edite no início do arquivo:"
echo "   APN=\"zap.vivo.com.br\"  # Sua operadora"
echo "   USER=\"vivo\""
echo "   PASS=\"vivo\""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  CONECTAR MODEMS USB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Conecte os modems 4G na máquina"
echo "   Verifique com: mmcli -L"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  INICIAR SISTEMA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   sudo $USER_HOME/proxy-system/proxy-manager.sh start"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  INICIAR API:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   sudo systemctl start proxy-api"
echo "   sudo systemctl enable proxy-api"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  HABILITAR INICIALIZAÇÃO AUTOMÁTICA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   sudo systemctl enable proxy-system"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6️⃣  ACESSAR DASHBOARD:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   http://SEU_IP:5000"
echo ""
echo "========================================="
echo "📊 COMANDOS ÚTEIS:"
echo "========================================="
echo ""
echo "  Ver status API:"
echo "    sudo systemctl status proxy-api"
echo ""
echo "  Ver logs API (tempo real):"
echo "    sudo journalctl -u proxy-api -f"
echo ""
echo "  Ver status sistema:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh status"
echo ""
echo "  Renovar IP de porta específica:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh renew-port 6001"
echo ""
echo "  Reiniciar sistema completo:"
echo "    sudo $USER_HOME/proxy-system/proxy-manager.sh restart"
echo ""
echo "  Testar proxy HTTP:"
echo "    curl -x http://127.0.0.1:6001 https://api.ipify.org"
echo ""
echo "  Testar proxy SOCKS5:"
echo "    curl --socks5 127.0.0.1:7001 https://api.ipify.org"
echo ""
echo "========================================="
echo "🔗 MODEMS DETECTADOS:"
echo "========================================="
mmcli -L 2>/dev/null || echo "  ⚠️  Nenhum modem detectado ainda."
echo "     Conecte os modems USB e execute: mmcli -L"
echo ""
echo "========================================="
echo "✨ INSTALAÇÃO FINALIZADA!"
echo "========================================="
echo ""
echo "📂 Arquivos instalados de: $SCRIPT_DIR"
echo "📂 Sistema instalado em: $USER_HOME"
echo ""
echo "Sistema pronto para uso! 🚀"
echo ""