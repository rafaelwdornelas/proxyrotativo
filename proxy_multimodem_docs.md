# 📡 Sistema Multi-Modem Proxy - Documentação Completa

**Versão:** 1.0  
**Sistema Operacional:** Ubuntu 20.04+ (Server/Desktop)  
**Autor:** Documentação para ambiente de testes

---

## 📋 Índice

1. [Pré-requisitos](#pré-requisitos)
2. [Instalação do Sistema Base](#1-atualização-do-sistema)
3. [Instalação do 3proxy](#3-instalação-do-3proxy)
4. [Criação do Script de Gerenciamento](#5-criar-script-de-gerenciamento)
5. [Configuração de Renovação Automática](#6-configurar-renovação-automática-de-ips)
6. [Comandos de Uso](#7-comandos-de-uso)
7. [Troubleshooting](#8-troubleshooting)
8. [Configurações para Outras Operadoras](#9-configurações-para-outras-operadoras)

---

## Pré-requisitos

### Hardware
- Servidor/PC Ubuntu 20.04 ou superior
- 2 a 10 modems 4G USB
- Hub USB com **alimentação externa** (obrigatório para 3+ modems)
- Mínimo 2GB RAM (recomendado 4GB+ para 5+ modems)

### Software
- Acesso root (sudo)
- Conexão com internet (para instalação inicial)

### Operadora
- APN configurado (exemplo: `zap.vivo.com.br` para Vivo)
- Credenciais de autenticação (usuário/senha)

---

## 1. Atualização do Sistema

```bash
# Atualizar repositórios e pacotes
sudo apt update && sudo apt upgrade -y

# Reiniciar se houver atualização de kernel
sudo reboot
```

---

## 2. Instalação de Dependências

```bash
# ModemManager e ferramentas de rede
sudo apt install -y modemmanager network-manager libqmi-utils libmbim-utils usb-modeswitch

# Ferramentas de compilação
sudo apt install -y build-essential git

# Ferramentas adicionais
sudo apt install -y curl wget net-tools iptables ufw

# Verificar se ModemManager está rodando
sudo systemctl status ModemManager

# Se não estiver ativo, iniciar
sudo systemctl enable ModemManager
sudo systemctl start ModemManager
```

---

## 3. Instalação do 3proxy

```bash
# Criar diretório temporário
cd /tmp

# Baixar código-fonte
wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz

# Extrair
tar -xzf 0.9.4.tar.gz
cd 3proxy-0.9.4

# Compilar
make -f Makefile.Linux

# Criar diretórios necessários
sudo mkdir -p /usr/local/bin
sudo mkdir -p /etc/3proxy
sudo mkdir -p /var/log/3proxy

# Instalar binário
sudo cp bin/3proxy /usr/local/bin/
sudo chmod +x /usr/local/bin/3proxy

# Verificar instalação
/usr/local/bin/3proxy --version
```

**Saída esperada:** `3proxy 0.9.4`

---

## 4. Verificar Modems Detectados

```bash
# Listar modems conectados
mmcli -L

# Ver detalhes de um modem específico (substitua 0 pelo número do modem)
mmcli -m 0

# Se nenhum modem aparecer, reiniciar serviço
sudo systemctl restart ModemManager
sleep 5
mmcli -L
```

**Saída esperada:**
```
/org/freedesktop/ModemManager1/Modem/0 [QUALCOMM] SIMCOM_SIM7600E-H
/org/freedesktop/ModemManager1/Modem/1 [QUALCOMM] SIMCOM_SIM7600E-H
```

---

## 5. Criar Script de Gerenciamento

### 5.1. Criar usuário squid (opcional)

```bash
sudo useradd -m -s /bin/bash squid
```

### 5.2. Criar o script

```bash
# Criar arquivo
sudo nano /home/squid/proxy-manager-complete.sh
```

### 5.3. Colar o conteúdo completo

```bash
#!/bin/bash
# Proxy Manager - Multi-Modem Automático (VERSÃO FUNCIONAL)

APN="zap.vivo.com.br"
USER="vivo"
PASS="vivo"
BASE_PROXY_PORT=6000
BASE_SOCKS_PORT=6100
STATE_FILE="/var/run/proxy-manager-rotation-state"

# Arrays para modems funcionais
declare -a WORKING_MODEMS
declare -a WORKING_IPS
declare -a WORKING_GATEWAYS
declare -a WORKING_INTERFACES

# Detectar TODOS os modems funcionais
detect_all_modems() {
    echo "🔍 Detectando todos os modems funcionais..."
    
    MODEMS=$(mmcli -L | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    
    for MODEM in $MODEMS; do
        echo ""
        echo "Testando modem $MODEM..."
        
        # Desconectar
        mmcli -m $MODEM --simple-disconnect 2>/dev/null
        sleep 3
        
        # Conectar
        if mmcli -m $MODEM --simple-connect="apn=$APN,user=$USER,password=$PASS,ip-type=ipv4" 2>/dev/null; then
            sleep 10
            
            # Pegar configuração
            BEARER=$(mmcli -m $MODEM | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
            IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
            GATEWAY=$(mmcli -b $BEARER 2>/dev/null | grep "gateway:" | awk '{print $3}')
            PREFIX=$(mmcli -b $BEARER 2>/dev/null | grep "prefix:" | awk '{print $3}')
            INTERFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
            
            if [ -z "$IP" ] || [ -z "$INTERFACE" ]; then
                echo "  ❌ Modem $MODEM: sem IP/interface"
                continue
            fi
            
            echo "  📡 Modem $MODEM: $INTERFACE ($IP)"
            
            # Configurar interface
            ip addr flush dev $INTERFACE 2>/dev/null
            ip addr add $IP/$PREFIX dev $INTERFACE
            ip link set $INTERFACE up
            
            # Testar conectividade
            echo "  🔄 Testando ping..."
            if timeout 10 ping -I $INTERFACE -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
                echo "  ✅ Modem $MODEM FUNCIONA!"
                
                # Adicionar aos arrays
                WORKING_MODEMS+=($MODEM)
                WORKING_IPS+=($IP)
                WORKING_GATEWAYS+=($GATEWAY)
                WORKING_INTERFACES+=($INTERFACE)
            else
                echo "  ❌ Modem $MODEM: sem conectividade (ping falhou)"
            fi
        else
            echo "  ❌ Modem $MODEM: falha ao conectar"
        fi
    done
    
    echo ""
    echo "========================================="
    if [ ${#WORKING_MODEMS[@]} -eq 0 ]; then
        echo "❌ ERRO: Nenhum modem funcional!"
        return 1
    else
        echo "✅ Modems funcionais: ${#WORKING_MODEMS[@]}"
        for i in "${!WORKING_MODEMS[@]}"; do
            echo "   Modem ${WORKING_MODEMS[$i]}: ${WORKING_INTERFACES[$i]} (${WORKING_IPS[$i]})"
        done
        return 0
    fi
}

# Configurar sistema com todos os modems
setup_system() {
    echo ""
    echo "⚙️  Configurando sistema multi-modem..."
    
    # Limpar arquivo rt_tables de duplicatas
    cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.backup
    grep -v "wwan" /etc/iproute2/rt_tables > /tmp/rt_tables.tmp
    mv /tmp/rt_tables.tmp /etc/iproute2/rt_tables
    
    # Limpar TODAS regras antigas de fwmark (por priority)
    for PRIO in {100..150}; do
        ip rule del priority $PRIO 2>/dev/null || true
    done
    
    # Configurar rotas e iptables para cada modem
    for i in "${!WORKING_MODEMS[@]}"; do
        IFACE=${WORKING_INTERFACES[$i]}
        GATEWAY=${WORKING_GATEWAYS[$i]}
        
        # Rota padrão com métrica diferente para cada
        METRIC=$((10 + i))
        ip route del default via $GATEWAY dev $IFACE 2>/dev/null
        ip route add default via $GATEWAY dev $IFACE metric $METRIC
        
        # Tabela de roteamento individual (wwan0=101, wwan1=100, wwan2=102, etc)
        if [ "$IFACE" == "wwan0" ]; then
            TABLE_ID=101
        elif [ "$IFACE" == "wwan1" ]; then
            TABLE_ID=100
        else
            TABLE_ID=$((102 + i))
        fi
        TABLE_NAME="${IFACE}_table"
        
        # Adicionar ao rt_tables
        echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables
        
        # Popular tabela
        ip route flush table $TABLE_ID 2>/dev/null || true
        ip route add default via $GATEWAY dev $IFACE table $TABLE_ID
        
        # NAT
        iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null
        iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
        
        # Marcação de pacotes por porta
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        MARK=$((i + 1))
        
        iptables -t mangle -D OUTPUT -p tcp --sport $PROXY_PORT -j MARK --set-mark $MARK 2>/dev/null
        iptables -t mangle -A OUTPUT -p tcp --sport $PROXY_PORT -j MARK --set-mark $MARK
        iptables -t mangle -D OUTPUT -p tcp --sport $SOCKS_PORT -j MARK --set-mark $MARK 2>/dev/null
        iptables -t mangle -A OUTPUT -p tcp --sport $SOCKS_PORT -j MARK --set-mark $MARK
        
        # Regra de roteamento: MARK → TABELA usando priority
        PRIORITY=$((100 + i))
        ip rule add from all fwmark $MARK table $TABLE_ID priority $PRIORITY
        
        echo "  ✓ $IFACE: Porta $PROXY_PORT → MARK $MARK → Tabela $TABLE_ID (priority $PRIORITY)"
    done
    
    # Criar configuração do 3proxy SEM -e
    cat > /etc/3proxy/3proxy.cfg << EOF
daemon
log /var/log/3proxy/3proxy.log D
rotate 30
auth none
allow *

EOF
    
    # Proxies individuais (1 por modem) - SEM -e
    for i in "${!WORKING_MODEMS[@]}"; do
        IP=${WORKING_IPS[$i]}
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        
        cat >> /etc/3proxy/3proxy.cfg << EOF
# Modem ${WORKING_MODEMS[$i]} (${WORKING_INTERFACES[$i]} - $IP)
proxy -p$PROXY_PORT -i0.0.0.0
socks -p$SOCKS_PORT -i0.0.0.0

EOF
    done
    
    # Proxies rotativos (se tiver mais de 1 modem)
    if [ ${#WORKING_MODEMS[@]} -gt 1 ]; then
        cat >> /etc/3proxy/3proxy.cfg << EOF
# Proxies rotativos (alternam entre todos os modems)
$(for j in {1..3}; do
    PORT=$((BASE_PROXY_PORT + 50 + j))
    echo "proxy -p$PORT -i0.0.0.0"
done)

$(for j in {1..3}; do
    PORT=$((BASE_SOCKS_PORT + 50 + j))
    echo "socks -p$PORT -i0.0.0.0"
done)
EOF
    fi
    
    # Configurar firewall UFW automaticamente
    echo ""
    echo "🔥 Configurando firewall..."
    
    # Habilitar UFW se não estiver
    ufw --force enable > /dev/null 2>&1
    
    # Liberar portas dedicadas
    for i in "${!WORKING_MODEMS[@]}"; do
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        ufw allow $PROXY_PORT/tcp > /dev/null 2>&1
        ufw allow $SOCKS_PORT/tcp > /dev/null 2>&1
    done
    
    # Liberar portas rotativas
    for j in {1..3}; do
        ufw allow $((BASE_PROXY_PORT + 50 + j))/tcp > /dev/null 2>&1
        ufw allow $((BASE_SOCKS_PORT + 50 + j))/tcp > /dev/null 2>&1
    done
    
    # Liberar SSH
    ufw allow 22/tcp > /dev/null 2>&1
    
    # Recarregar firewall
    ufw reload > /dev/null 2>&1
    
    echo "  ✓ Firewall configurado (portas liberadas)"
    
    # Reiniciar 3proxy
    killall 3proxy 2>/dev/null
    sleep 2
    /usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
    
    echo ""
    echo "========================================="
    echo "✅ SISTEMA CONFIGURADO!"
    echo "========================================="
    echo ""
    echo "PROXIES DEDICADOS (1 por modem):"
    for i in "${!WORKING_MODEMS[@]}"; do
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        echo "  Modem ${WORKING_MODEMS[$i]} - HTTP: $PROXY_PORT | SOCKS5: $SOCKS_PORT (${WORKING_INTERFACES[$i]}: ${WORKING_IPS[$i]})"
    done
    
    if [ ${#WORKING_MODEMS[@]} -gt 1 ]; then
        echo ""
        echo "PROXIES ROTATIVOS (alternam entre modems):"
        echo "  HTTP: 6051, 6052, 6053"
        echo "  SOCKS5: 6151, 6152, 6153"
    fi
    echo ""
    echo "========================================="
}

# Renovação rotativa - apenas 1 modem por vez
renew_single_modem() {
    echo "🔄 Renovação rotativa de IP (um modem por vez)"
    echo ""
    
    # Criar arquivo de estado se não existir
    if [ ! -f "$STATE_FILE" ]; then
        echo "0" > "$STATE_FILE"
    fi
    
    # Detectar modems ativos
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2 | sort)
    MODEM_ARRAY=($MODEMS)
    TOTAL_MODEMS=${#MODEM_ARRAY[@]}
    
    if [ $TOTAL_MODEMS -eq 0 ]; then
        echo "❌ ERRO: Nenhum modem detectado"
        return 1
    fi
    
    # Ler último modem renovado e calcular próximo
    LAST_INDEX=$(cat "$STATE_FILE")
    NEXT_INDEX=$(( (LAST_INDEX + 1) % TOTAL_MODEMS ))
    MODEM_TO_RENEW=${MODEM_ARRAY[$NEXT_INDEX]}
    
    echo "📡 Renovando modem $MODEM_TO_RENEW (índice $NEXT_INDEX/$TOTAL_MODEMS)"
    echo ""
    
    # Desconectar modem específico
    mmcli -m $MODEM_TO_RENEW --simple-disconnect 2>/dev/null
    sleep 5
    
    # Reconectar
    if mmcli -m $MODEM_TO_RENEW --simple-connect="apn=$APN,user=$USER,password=$PASS,ip-type=ipv4" 2>/dev/null; then
        sleep 10
        
        # Obter nova configuração
        BEARER=$(mmcli -m $MODEM_TO_RENEW | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        NEW_IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
        GATEWAY=$(mmcli -b $BEARER 2>/dev/null | grep "gateway:" | awk '{print $3}')
        PREFIX=$(mmcli -b $BEARER 2>/dev/null | grep "prefix:" | awk '{print $3}')
        INTERFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
        
        if [ -n "$NEW_IP" ] && [ -n "$INTERFACE" ]; then
            echo "  🆕 Novo IP: $NEW_IP ($INTERFACE)"
            
            # Reconfigurar interface
            ip addr flush dev $INTERFACE 2>/dev/null
            ip addr add $NEW_IP/$PREFIX dev $INTERFACE
            ip link set $INTERFACE up
            
            # Reconfigurar rota padrão
            METRIC=$((10 + NEXT_INDEX))
            ip route del default via $GATEWAY dev $INTERFACE 2>/dev/null
            ip route add default via $GATEWAY dev $INTERFACE metric $METRIC
            
            # Atualizar tabela de roteamento dedicada
            if [ "$INTERFACE" == "wwan0" ]; then
                TABLE_ID=101
            elif [ "$INTERFACE" == "wwan1" ]; then
                TABLE_ID=100
            else
                TABLE_ID=$((102 + NEXT_INDEX))
            fi
            
            ip route flush table $TABLE_ID 2>/dev/null
            ip route add default via $GATEWAY dev $INTERFACE table $TABLE_ID
            
            # Reconfigurar NAT (garante MASQUERADE)
            iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null
            iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
            
            # Testar conectividade
            echo "  🔄 Testando conectividade..."
            if timeout 10 ping -I $INTERFACE -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
                echo "  ✅ Modem $MODEM_TO_RENEW renovado com sucesso!"
                echo ""
                
                # Calcular próximo modem
                NEXT_MODEM_INDEX=$(( (NEXT_INDEX + 1) % TOTAL_MODEMS ))
                NEXT_MODEM=${MODEM_ARRAY[$NEXT_MODEM_INDEX]}
                
                echo "========================================="
                echo "✅ IP RENOVADO"
                echo "========================================="
                echo "Modem renovado: $MODEM_TO_RENEW"
                echo "Interface: $INTERFACE"
                echo "IP novo: $NEW_IP"
                echo "Próxima renovação: Modem $NEXT_MODEM"
                echo "========================================="
                
                # Salvar estado
                echo "$NEXT_INDEX" > "$STATE_FILE"
                return 0
            else
                echo "  ⚠️  Modem $MODEM_TO_RENEW: IP renovado mas sem conectividade"
                return 1
            fi
        else
            echo "  ❌ Erro ao obter novo IP do modem $MODEM_TO_RENEW"
            return 1
        fi
    else
        echo "  ❌ Erro ao reconectar modem $MODEM_TO_RENEW"
        return 1
    fi
}

# Status
show_status() {
    echo "=== STATUS DO SISTEMA ==="
    echo ""
    
    # Modems
    echo "MODEMS:"
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    for M in $MODEMS; do
        STATE=$(mmcli -m $M 2>/dev/null | grep "state:" | awk '{print $3}')
        SIGNAL=$(mmcli -m $M 2>/dev/null | grep "signal quality" | awk '{print $4}')
        echo "  Modem $M: $STATE (Sinal: $SIGNAL)"
    done
    
    echo ""
    
    # 3proxy
    if pgrep 3proxy > /dev/null; then
        echo "3PROXY: ✅ RODANDO"
        echo ""
        echo "Testando IPs externos:"
        
        # Testar portas dedicadas
        for PORT in 6001 6002; do
            if netstat -tlnp 2>/dev/null | grep -q ":$PORT "; then
                IP=$(timeout 5 curl -s -x http://127.0.0.1:$PORT https://api.ipify.org 2>/dev/null)
                if [ -n "$IP" ]; then
                    echo "  Porta $PORT: $IP"
                else
                    echo "  Porta $PORT: TIMEOUT"
                fi
            fi
        done
        
        # Testar proxy rotativo
        if netstat -tlnp 2>/dev/null | grep -q ":6051 "; then
            IP=$(timeout 5 curl -s -x http://127.0.0.1:6051 https://api.ipify.org 2>/dev/null)
            if [ -n "$IP" ]; then
                echo "  Porta 6051 (rotativo): $IP"
            fi
        fi
    else
        echo "3PROXY: ❌ PARADO"
    fi
    echo ""
}

# Parar
stop_system() {
    echo "Parando sistema..."
    killall 3proxy 2>/dev/null
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    for M in $MODEMS; do
        mmcli -m $M --simple-disconnect 2>/dev/null
    done
    echo "Sistema parado"
}

# Menu
case "$1" in
    start)
        if detect_all_modems; then
            setup_system
        fi
        ;;
    stop)
        stop_system
        ;;
    restart)
        stop_system
        sleep 3
        if detect_all_modems; then
            setup_system
        fi
        ;;
    renew)
        # Renovação rotativa (um modem por vez)
        renew_single_modem
        ;;
    renew-all)
        # Renovação completa (todos os modems - antiga funcionalidade)
        echo "⚠️  Renovando TODOS os modems (sistema será reiniciado)"
        stop_system
        sleep 3
        if detect_all_modems; then
            setup_system
        fi
        ;;
    status)
        show_status
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|renew|renew-all|status}"
        echo ""
        echo "  start      - Inicia sistema"
        echo "  stop       - Para sistema"
        echo "  restart    - Reinicia sistema completo"
        echo "  renew      - Renova IP de UM modem (rotativo)"
        echo "  renew-all  - Renova IPs de TODOS os modems"
        echo "  status     - Mostra status"
        exit 1
        ;;
esac
```

### 5.4. Dar permissão de execução

```bash
sudo chmod +x /home/squid/proxy-manager-complete.sh
```

---

## 6. Configurar Renovação Automática de IPs

### 6.1. Criar arquivo de log

```bash
sudo touch /var/log/proxy-renew-rotation.log
sudo chmod 644 /var/log/proxy-renew-rotation.log
```

### 6.2. Configurar cron

```bash
sudo crontab -e
```

### 6.3. Adicionar linha

```bash
# Renovar IP rotativo (um modem por vez) a cada 5 minutos
*/5 * * * * /home/squid/proxy-manager-complete.sh renew >> /var/log/proxy-renew-rotation.log 2>&1
```

**Salvar e sair:** `Ctrl+O` → `Enter` → `Ctrl+X`

### 6.4. Verificar cron configurado

```bash
sudo crontab -l
```

---

## 7. Comandos de Uso

### 7.1. Iniciar sistema

```bash
sudo /home/squid/proxy-manager-complete.sh start
```

### 7.2. Ver status

```bash
sudo /home/squid/proxy-manager-complete.sh status
```

### 7.3. Renovar IP de um modem (rotativo)

```bash
sudo /home/squid/proxy-manager-complete.sh renew
```

### 7.4. Renovar IPs de todos os modems

```bash
sudo /home/squid/proxy-manager-complete.sh renew-all
```

### 7.5. Reiniciar sistema completo

```bash
sudo /home/squid/proxy-manager-complete.sh restart
```

### 7.6. Parar sistema

```bash
sudo /home/squid/proxy-manager-complete.sh stop
```

### 7.7. Monitorar log de renovação

```bash
sudo tail -f /var/log/proxy-renew-rotation.log
```

### 7.8. Testar proxies

```bash
# Testar proxy HTTP dedicado (porta 6001)
curl -x http://IP_SERVIDOR:6001 https://api.ipify.org

# Testar proxy SOCKS5 dedicado (porta 6101)
curl --socks5 IP_SERVIDOR:6101 https://api.ipify.org

# Testar proxy rotativo (porta 6051)
curl -x http://IP_SERVIDOR:6051 https://api.ipify.org
```

---

## 8. Troubleshooting

### 8.1. Modems não detectados

```bash
# Verificar se modems estão conectados via USB
lsusb

# Reiniciar ModemManager
sudo systemctl restart ModemManager
sleep 5
mmcli -L

# Ver logs do ModemManager
sudo journalctl -u ModemManager -f
```

### 8.2. Modems detectados mas sem conexão

```bash
# Verificar sinal do modem
mmcli -m 0 | grep signal

# Conectar manualmente
sudo mmcli -m 0 --simple-connect="apn=zap.vivo.com.br,user=vivo,password=vivo,ip-type=ipv4"

# Ver status da conexão
mmcli -m 0
```

### 8.3. 3proxy não inicia

```bash
# Verificar se o binário existe
ls -la /usr/local/bin/3proxy

# Testar configuração
sudo /usr/local/bin/3proxy /etc/3proxy/3proxy.cfg

# Ver log do 3proxy
sudo tail -f /var/log/3proxy/3proxy.log

# Verificar processos
ps aux | grep 3proxy
```

### 8.4. Proxy não responde

```bash
# Verificar se portas estão abertas
sudo netstat -tlnp | grep 3proxy

# Testar localmente
curl -x http://127.0.0.1:6001 https://api.ipify.org

# Verificar firewall
sudo ufw status

# Liberar portas manualmente
sudo ufw allow 6001:6010/tcp
sudo ufw allow 6101:6110/tcp
sudo ufw reload
```

### 8.5. Renovação automática não funciona

```bash
# Verificar se cron está ativo
sudo systemctl status cron

# Ver último erro
sudo tail -20 /var/log/proxy-renew-rotation.log

# Testar renovação manual
sudo /home/squid/proxy-manager-complete.sh renew

# Verificar arquivo de estado
cat /var/run/proxy-manager-rotation-state
```

### 8.6. IP não muda na renovação

```bash
# Forçar desconexão completa
sudo mmcli -m 0 --simple-disconnect
sleep 10
sudo mmcli -m 0 --simple-connect="apn=zap.vivo.com.br,user=vivo,password=vivo,ip-type=ipv4"

# Verificar novo IP
mmcli -m 0 | grep -i "ipv4 config"
```

---

## 9. Configurações para Outras Operadoras

Edite as variáveis no início do script `/home/squid/proxy-manager-complete.sh`:

### 9.1. Vivo

```bash
APN="zap.vivo.com.br"
USER="vivo"
PASS="vivo"
```

### 9.2. Claro

```bash
APN="claro.com.br"
USER="claro"
PASS="claro"
```

### 9.3. TIM

```bash
APN="tim.br"
USER="tim"
PASS="tim"
```

### 9.4. Oi

```bash
APN="gprs.oi.com.br"
USER="oi"
PASS="oi"
```

---

## 10. Estrutura de Portas

### Portas Dedicadas (1 proxy por modem)

| Modem | HTTP Proxy | SOCKS5 Proxy |
|-------|-----------|--------------|
| 0     | 6001      | 6101         |
| 1     | 6002      | 6102         |
| 2     | 6003      | 6103         |
| 3     | 6004      | 6104         |
| ...   | ...       | ...          |
| 9     | 6010      | 6110         |

### Portas Rotativas (alternam entre modems)

| Tipo        | Portas           |
|-------------|------------------|
| HTTP Proxy  | 6051, 6052, 6053 |
| SOCKS5      | 6151, 6152, 6153 |

---

## 11. Arquivos Importantes

| Arquivo | Descrição |
|---------|-----------|
| `/home/squid/proxy-manager-complete.sh` | Script principal |
| `/etc/3proxy/3proxy.cfg` | Configuração do 3proxy |
| `/var/log/3proxy/3proxy.log` | Log do 3proxy |
| `/var/log/proxy-renew-rotation.log` | Log de renovação de IPs |
| `/var/run/proxy-manager-rotation-state` | Estado da rotação (índice do último modem renovado) |
| `/etc/iproute2/rt_tables` | Tabelas de roteamento |

---

## 12. Limpeza/Desinstalação

```bash
# Parar sistema
sudo /home/squid/proxy-manager-complete.sh stop

# Remover cron
sudo crontab -e
# Deletar a linha de renovação

# Remover arquivos
sudo rm /home/squid/proxy-manager-complete.sh
sudo rm -rf /etc/3proxy
sudo rm -rf /var/log/3proxy
sudo rm /var/log/proxy-renew-rotation.log
sudo rm /var/run/proxy-manager-rotation-state

# Remover 3proxy
sudo rm /usr/local/bin/3proxy

# Limpar iptables (opcional)
sudo iptables -t nat -F
sudo iptables -t mangle -F
```

---

## 13. Suporte e Contato

Este sistema foi desenvolvido para ambiente de **testes e pesquisa** em segurança da informação.

**Não usar em produção sem auditoria de segurança adequada.**

---

**Versão:** 1.0  
**Última atualização:** 2025