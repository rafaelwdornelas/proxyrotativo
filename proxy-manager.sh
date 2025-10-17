#!/bin/bash
# Proxy Manager - Sistema Multi-Modem (Versão Final Completa e Testada)

# Configurações
APN="zap.vivo.com.br"
USER="vivo"
PASS="vivo"
BASE_PROXY_PORT=6000
BASE_SOCKS_PORT=6100

# Arrays para modems funcionais
declare -a WORKING_MODEMS
declare -a WORKING_IPS
declare -a WORKING_GATEWAYS
declare -a WORKING_INTERFACES

# Detectar TODOS os modems funcionais
detect_all_modems() {
    echo "🔍 Detectando modems funcionais..."
    
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    
    if [ -z "$MODEMS" ]; then
        echo "❌ Nenhum modem detectado!"
        return 1
    fi
    
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
            BEARER=$(mmcli -m $MODEM 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
            
            if [ -z "$BEARER" ]; then
                echo "  ❌ Modem $MODEM: sem bearer"
                continue
            fi
            
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
            ip addr add $IP/$PREFIX dev $INTERFACE 2>/dev/null
            ip link set $INTERFACE up 2>/dev/null
            
            # Testar conectividade
            echo "  🔄 Testando conectividade..."
            if timeout 10 ping -I $INTERFACE -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
                echo "  ✅ Modem $MODEM FUNCIONA!"
                
                WORKING_MODEMS+=($MODEM)
                WORKING_IPS+=($IP)
                WORKING_GATEWAYS+=($GATEWAY)
                WORKING_INTERFACES+=($INTERFACE)
            else
                echo "  ❌ Modem $MODEM: sem conectividade"
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

# Configurar policy routing por IP de origem
setup_policy_routing() {
    echo "  🔀 Configurando policy routing..."
    
    # Remover regras antigas de policy routing (priority 90-99)
    for PRIO in {90..99}; do
        ip rule del priority $PRIO 2>/dev/null || true
    done
    
    # Detectar IPs atuais e criar regras
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2 | sort)
    
    PRIORITY=99
    for MODEM in $MODEMS; do
        BEARER=$(mmcli -m $MODEM 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        if [ -n "$BEARER" ]; then
            IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
            IFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
            
            if [ -n "$IP" ] && [ -n "$IFACE" ]; then
                # Descobrir TABLE_ID baseado na interface
                if [ "$IFACE" == "wwan0" ]; then
                    TABLE_ID=101
                elif [ "$IFACE" == "wwan1" ]; then
                    TABLE_ID=100
                else
                    TABLE_ID=$((102 + $(echo $MODEMS | tr ' ' '\n' | grep -n "^$MODEM$" | cut -d: -f1)))
                fi
                
                # Adicionar regra de policy routing por IP de origem
                ip rule add from $IP table $TABLE_ID priority $PRIORITY 2>/dev/null || true
                echo "    ✓ IP $IP → Tabela $TABLE_ID (priority $PRIORITY)"
                
                PRIORITY=$((PRIORITY - 1))
            fi
        fi
    done
    
    # Limpar cache de rotas
    ip route flush cache 2>/dev/null || true
    
    echo "  ✓ Policy routing configurado"
}

# Configurar sistema
setup_system() {
    echo ""
    echo "⚙️  Configurando sistema..."
    
    # Limpar rt_tables
    cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.backup 2>/dev/null
    grep -v "wwan" /etc/iproute2/rt_tables 2>/dev/null > /tmp/rt_tables.tmp
    mv /tmp/rt_tables.tmp /etc/iproute2/rt_tables
    
    # Limpar regras antigas
    for PRIO in {100..150}; do
        ip rule del priority $PRIO 2>/dev/null || true
    done
    
    # Configurar cada modem
    for i in "${!WORKING_MODEMS[@]}"; do
        IFACE=${WORKING_INTERFACES[$i]}
        GATEWAY=${WORKING_GATEWAYS[$i]}
        
        # Rota padrão com métrica diferente
        METRIC=$((10 + i))
        ip route del default via $GATEWAY dev $IFACE 2>/dev/null || true
        ip route add default via $GATEWAY dev $IFACE metric $METRIC
        
        # Tabela de roteamento individual
        TABLE_ID=$((100 + i))
        TABLE_NAME="${IFACE}_table"
        
        echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables
        
        ip route flush table $TABLE_ID 2>/dev/null || true
        ip route add default via $GATEWAY dev $IFACE table $TABLE_ID
        
        # NAT
        iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
        
        # FORWARD rules (permitir tráfego da LAN para modems)
        iptables -A FORWARD -i ens33 -o $IFACE -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -i $IFACE -o ens33 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        
        # Marcação de pacotes por porta
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        MARK=$((i + 1))
        
        
        # Regra de roteamento por marca
        PRIORITY=$((100 + i))
        ip rule add from all fwmark $MARK table $TABLE_ID priority $PRIORITY 2>/dev/null || true
        
        echo "  ✓ $IFACE: HTTP=$PROXY_PORT SOCKS=$SOCKS_PORT → Tabela $TABLE_ID"
    done
    
    # Habilitar IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Tornar IP forwarding permanente
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Criar config do 3proxy
    cat > /etc/3proxy/3proxy.cfg << EOF
daemon
log /var/log/3proxy/3proxy.log D
rotate 30
auth none
allow *

EOF
    
    # Proxies individuais (1 por modem) - CORREÇÃO: bind em 0.0.0.0, saída pelo IP do modem
for i in "${!WORKING_MODEMS[@]}"; do
    IP=${WORKING_IPS[$i]}
    IFACE=${WORKING_INTERFACES[$i]}
    PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
    SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
    
    cat >> /etc/3proxy/3proxy.cfg << EOF
# Modem ${WORKING_MODEMS[$i]} - $IFACE ($IP)
proxy -p$PROXY_PORT -e$IP
socks -p$SOCKS_PORT -e$IP

EOF
done
    
    # Iniciar 3proxy
    killall 3proxy 2>/dev/null || true
    sleep 2
    /usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
    
    # Configurar policy routing por IP de origem
    setup_policy_routing
    
    echo ""
    echo "========================================="
    echo "✅ SISTEMA CONFIGURADO!"
    echo "========================================="
    echo ""
    echo "PROXIES ATIVOS:"
    for i in "${!WORKING_MODEMS[@]}"; do
        PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
        SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
        echo "  Porta HTTP $PROXY_PORT | SOCKS5 $SOCKS_PORT → Modem ${WORKING_MODEMS[$i]} (${WORKING_INTERFACES[$i]}: ${WORKING_IPS[$i]})"
    done
    echo ""
    echo "API: http://SEU_IP:5000"
    echo "========================================="
}

# Reconstruir config do 3proxy após renovação
rebuild_3proxy_config() {
    echo "  🔄 Atualizando 3proxy..."
    
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2 | sort)
    
    declare -a CURRENT_IPS
    declare -a CURRENT_INTERFACES
    declare -a CURRENT_MODEMS
    
    for MODEM in $MODEMS; do
        BEARER=$(mmcli -m $MODEM 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        if [ -n "$BEARER" ]; then
            IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
            IFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
            
            if [ -n "$IP" ] && [ -n "$IFACE" ]; then
                CURRENT_MODEMS+=($MODEM)
                CURRENT_IPS+=($IP)
                CURRENT_INTERFACES+=($IFACE)
            fi
        fi
    done
    
    # Recriar config
    cat > /etc/3proxy/3proxy.cfg << EOF
daemon
log /var/log/3proxy/3proxy.log D
rotate 30
auth none
allow *

EOF
    
    for i in "${!CURRENT_IPS[@]}"; do
    IP=${CURRENT_IPS[$i]}
    IFACE=${CURRENT_INTERFACES[$i]}
    MODEM=${CURRENT_MODEMS[$i]}
    PROXY_PORT=$((BASE_PROXY_PORT + i + 1))
    SOCKS_PORT=$((BASE_SOCKS_PORT + i + 1))
    
    cat >> /etc/3proxy/3proxy.cfg << EOF
# Modem $MODEM - $IFACE ($IP)
proxy -p$PROXY_PORT -e$IP
socks -p$SOCKS_PORT -e$IP

EOF
done
    
    # Reiniciar 3proxy
    killall 3proxy 2>/dev/null || true
    sleep 1
    /usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
    
    # Reconfigurar policy routing com novos IPs
    setup_policy_routing
    
    echo "  ✓ 3proxy reconfigurado"
}

# Renovar IP de porta específica (ModemManager - Otimizado)
renew_by_port() {
    TARGET_PORT=$1
    
    if [ -z "$TARGET_PORT" ]; then
        echo "❌ Erro: Porta não especificada"
        return 1
    fi
    
    echo "🔄 Renovando IP da porta $TARGET_PORT"
    echo ""
    
    # PASSO 1: Ler config do 3proxy para descobrir interface e IP interno
    if [ ! -f /etc/3proxy/3proxy.cfg ]; then
        echo "❌ Erro: Config do 3proxy não encontrada"
        return 1
    fi
    
    CONFIG_BLOCK=$(grep -B1 "^proxy -p$TARGET_PORT " /etc/3proxy/3proxy.cfg)
    
    if [ -z "$CONFIG_BLOCK" ]; then
        echo "❌ Erro: Porta $TARGET_PORT não encontrada no config do 3proxy"
        return 1
    fi
    
    TARGET_INTERFACE=$(echo "$CONFIG_BLOCK" | grep "^# Modem" | sed -n 's/.*- \([^ ]*\) (.*/\1/p')
    TARGET_INTERNAL_IP=$(echo "$CONFIG_BLOCK" | grep "^# Modem" | sed -n 's/.*(\([^)]*\)).*/\1/p')
    
    if [ -z "$TARGET_INTERFACE" ] || [ -z "$TARGET_INTERNAL_IP" ]; then
        echo "❌ Erro: Não foi possível extrair informações do config"
        return 1
    fi
    
    echo "  📋 Config da porta $TARGET_PORT:"
    echo "     Interface: $TARGET_INTERFACE"
    echo "     IP interno: $TARGET_INTERNAL_IP"
    echo ""
    
    # PASSO 2: Descobrir qual modem tem esse IP interno
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    
    MODEM_TO_RENEW=""
    MODEM_INDEX=""
    
    ACTIVE_INDEX=0
    
    for MODEM in $MODEMS; do
        BEARER=$(mmcli -m $MODEM 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        
        if [ -n "$BEARER" ]; then
            CURRENT_IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
            CURRENT_IFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
            
            if [ "$CURRENT_IP" == "$TARGET_INTERNAL_IP" ] || [ "$CURRENT_IFACE" == "$TARGET_INTERFACE" ]; then
                MODEM_TO_RENEW=$MODEM
                MODEM_INDEX=$ACTIVE_INDEX
                break
            fi
            
            ACTIVE_INDEX=$((ACTIVE_INDEX + 1))
        fi
    done
    
    if [ -z "$MODEM_TO_RENEW" ]; then
        echo "❌ Erro: Nenhum modem encontrado"
        return 1
    fi
    
    echo "  ✅ Modem identificado: $MODEM_TO_RENEW"
    echo ""
    
    # PASSO 3: Pegar IP público atual
    echo "  🌐 Obtendo IP público atual..."
    OLD_PUBLIC_IP=$(timeout 10 curl -s --interface $TARGET_INTERFACE https://api.ipify.org 2>/dev/null)
    
    if [ -z "$OLD_PUBLIC_IP" ]; then
        OLD_PUBLIC_IP="N/A"
        echo "  ⚠️  Não foi possível obter IP público antigo"
    else
        echo "  📍 IP público atual: $OLD_PUBLIC_IP"
    fi
    
    echo ""
    echo "📡 Iniciando renovação do Modem $MODEM_TO_RENEW..."
    
    # PASSO 4: Renovação otimizada
    MAX_ATTEMPTS=3
    ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo ""
        echo "  🔄 Tentativa $ATTEMPT de $MAX_ATTEMPTS..."
        
        # 1. Desconectar
        echo "  📴 Desconectando modem..."
        mmcli -m $MODEM_TO_RENEW --simple-disconnect 2>/dev/null
        
        # 2. Modo offline (força reset da sessão)
        echo "  🛑 Forçando reset de sessão..."
        mmcli -m $MODEM_TO_RENEW --set-power-state-low 2>/dev/null || true
        sleep 5
        
        # 3. Aguardar liberação do IP (REDUZIDO para 20s)
        echo "  ⏳ Aguardando liberação do IP (20s)..."
        sleep 20
        
        # 4. Modo online
        echo "  ⚡ Reativando modem..."
        mmcli -m $MODEM_TO_RENEW --set-power-state-on 2>/dev/null || true
        sleep 5
        
        # 5. Reconectar
        echo "  🔌 Reconectando..."
        if mmcli -m $MODEM_TO_RENEW --simple-connect="apn=$APN,user=$USER,password=$PASS,ip-type=ipv4" 2>/dev/null; then
            sleep 10
            
            # Obter nova configuração
            BEARER=$(mmcli -m $MODEM_TO_RENEW 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
            
            if [ -z "$BEARER" ]; then
                echo "  ❌ Falha ao obter bearer"
                ATTEMPT=$((ATTEMPT + 1))
                continue
            fi
            
            NEW_IP=$(mmcli -b $BEARER 2>/dev/null | grep "address:" | awk '{print $3}')
            GATEWAY=$(mmcli -b $BEARER 2>/dev/null | grep "gateway:" | awk '{print $3}')
            PREFIX=$(mmcli -b $BEARER 2>/dev/null | grep "prefix:" | awk '{print $3}')
            INTERFACE=$(mmcli -b $BEARER 2>/dev/null | grep "interface:" | awk '{print $3}')
            
            if [ -z "$NEW_IP" ] || [ -z "$INTERFACE" ]; then
                echo "  ❌ Falha ao obter configuração de rede"
                ATTEMPT=$((ATTEMPT + 1))
                continue
            fi
            
            echo "  🆕 Novo IP interno: $NEW_IP ($INTERFACE)"
            
            # Reconfigurar interface
            ip addr flush dev $INTERFACE 2>/dev/null
            ip addr add $NEW_IP/$PREFIX dev $INTERFACE
            ip link set $INTERFACE up
            
            # Reconfigurar rota
            METRIC=$((10 + MODEM_INDEX))
            ip route del default via $GATEWAY dev $INTERFACE 2>/dev/null || true
            ip route add default via $GATEWAY dev $INTERFACE metric $METRIC
            
            # Atualizar tabela de roteamento
            TABLE_ID=$((100 + MODEM_INDEX))
            ip route flush table $TABLE_ID 2>/dev/null || true
            ip route add default via $GATEWAY dev $INTERFACE table $TABLE_ID
            
            # Reconfigurar NAT
            iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || true
            iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
            
            # Testar conectividade
            echo "  🔄 Testando conectividade..."
            if timeout 10 ping -I $INTERFACE -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
                echo "  ✅ Conectividade OK"
                
                # Reconfigurar 3proxy
                echo "  🔄 Reconfigurando 3proxy..."
                rebuild_3proxy_config
                
                # Aguardar estabilização
                sleep 5
                
                # Obter NOVO IP público
                echo "  🌐 Obtendo novo IP público..."
                NEW_PUBLIC_IP=$(timeout 10 curl -s --interface $INTERFACE https://api.ipify.org 2>/dev/null)
                
                if [ -z "$NEW_PUBLIC_IP" ]; then
                    echo "  ⚠️  Não foi possível obter novo IP público"
                    ATTEMPT=$((ATTEMPT + 1))
                    continue
                fi
                
                echo "  📍 Novo IP público: $NEW_PUBLIC_IP"
                
                # Verificar se IP realmente mudou
                if [ "$NEW_PUBLIC_IP" != "$OLD_PUBLIC_IP" ] && [ "$OLD_PUBLIC_IP" != "N/A" ]; then
                    echo ""
                    echo "========================================="
                    echo "✅ IP RENOVADO COM SUCESSO"
                    echo "========================================="
                    echo "Porta: $TARGET_PORT"
                    echo "Modem: $MODEM_TO_RENEW"
                    echo "Interface: $INTERFACE"
                    echo "IP interno: $TARGET_INTERNAL_IP → $NEW_IP"
                    echo "IP público: $OLD_PUBLIC_IP → $NEW_PUBLIC_IP"
                    echo "========================================="
                    return 0
                elif [ "$OLD_PUBLIC_IP" == "N/A" ]; then
                    echo ""
                    echo "========================================="
                    echo "✅ MODEM RECONECTADO"
                    echo "========================================="
                    echo "Porta: $TARGET_PORT"
                    echo "Modem: $MODEM_TO_RENEW"
                    echo "Interface: $INTERFACE"
                    echo "IP interno: $NEW_IP"
                    echo "IP público: $NEW_PUBLIC_IP"
                    echo "========================================="
                    return 0
                else
                    echo "  ⚠️  IP não mudou: $NEW_PUBLIC_IP"
                    echo "  🔄 Operadora manteve o IP. Tentando novamente..."
                    ATTEMPT=$((ATTEMPT + 1))
                fi
            else
                echo "  ❌ Sem conectividade"
                ATTEMPT=$((ATTEMPT + 1))
            fi
        else
            echo "  ❌ Falha ao conectar"
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done
    
    echo ""
    echo "========================================="
    echo "❌ FALHA AO RENOVAR IP"
    echo "========================================="
    echo "Tentativas: $MAX_ATTEMPTS"
    if [ "$OLD_PUBLIC_IP" != "N/A" ]; then
        echo "IP permanece: $OLD_PUBLIC_IP"
    fi
    echo ""
    echo "Possíveis causas:"
    echo "- Operadora mantém IP por período mínimo"
    echo "- CGNAT com pool limitado de IPs"
    echo "- Necessário aguardar mais tempo"
    echo "========================================="
    return 1
}

# Status do sistema
show_status() {
    echo "========================================="
    echo "STATUS DO SISTEMA"
    echo "========================================="
    echo ""
    
    # Modems
    echo "📱 MODEMS:"
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    for M in $MODEMS; do
        STATE=$(mmcli -m $M 2>/dev/null | grep "state:" | awk '{print $3}')
        SIGNAL=$(mmcli -m $M 2>/dev/null | grep "signal quality" | awk '{print $4}')
        echo "  Modem $M: $STATE (Sinal: $SIGNAL)"
    done
    
    echo ""
    
    # 3proxy
    if pgrep 3proxy > /dev/null 2>&1; then
        echo "🔧 3PROXY: ✅ RODANDO"
        echo ""
        echo "🌐 IPs PÚBLICOS:"
        
        for PORT in 6001 6002 6003 6004 6005; do
            if netstat -tlnp 2>/dev/null | grep -q ":$PORT "; then
                # Descobrir qual IP do modem está na porta
                MODEM_IP=$(netstat -tlnp 2>/dev/null | grep ":$PORT " | awk '{print $4}' | cut -d: -f1 | head -1)
                if [ -n "$MODEM_IP" ] && [ "$MODEM_IP" != "0.0.0.0" ]; then
                    PUBLIC_IP=$(timeout 5 curl -s --interface $(ip addr | grep "$MODEM_IP" | awk '{print $NF}') https://api.ipify.org 2>/dev/null)
                    if [ -n "$PUBLIC_IP" ]; then
                        echo "  Porta $PORT ($MODEM_IP): $PUBLIC_IP"
                    fi
                fi
            fi
        done
    else
        echo "🔧 3PROXY: ❌ PARADO"
    fi
    
    echo ""
    echo "========================================="
}

# Parar sistema
stop_system() {
    echo "🛑 Parando sistema..."
    killall 3proxy 2>/dev/null || true
    MODEMS=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]" | cut -d'/' -f2)
    for M in $MODEMS; do
        mmcli -m $M --simple-disconnect 2>/dev/null || true
    done
    echo "✅ Sistema parado"
}

# Menu principal
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
    renew-port)
        if [ -z "$2" ]; then
            echo "Uso: $0 renew-port <PORTA>"
            echo "Exemplo: $0 renew-port 6001"
            exit 1
        fi
        renew_by_port $2
        ;;
    status)
        show_status
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|renew-port PORT|status}"
        echo ""
        echo "Comandos:"
        echo "  start           - Inicia sistema"
        echo "  stop            - Para sistema"
        echo "  restart         - Reinicia sistema completo"
        echo "  renew-port PORT - Renova IP de porta específica (ex: 6001)"
        echo "  status          - Mostra status"
        exit 1
        ;;
esac