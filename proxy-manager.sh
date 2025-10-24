#!/bin/bash

# ============================================================================
# Sistema de Gerenciamento de Proxies Multi-Modem
# Versão: 2.0 - Instância 3proxy por modem (Suporte até 100 modems)
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

APN="zap.vivo.com.br"
USER="vivo"
PASS="vivo"
BASE_PROXY_PORT=6000   # Portas HTTP: 6001-6100
BASE_SOCKS_PORT=7000   # Portas SOCKS5: 7001-7100
MAX_MODEMS=100
STATUS_FILE="/var/run/proxy-status.json"
LOG_DIR="/var/log/3proxy"
CONFIG_DIR="/etc/3proxy"
PID_DIR="/var/run"

# Arrays globais para modems detectados
declare -a DETECTED_MODEMS=()
declare -a DETECTED_INTERFACES=()
declare -a DETECTED_IPS=()
declare -a DETECTED_GATEWAYS=()
declare -a DETECTED_PREFIXES=()
declare -a DETECTED_PORTS=()

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $*"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*" >&2
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script precisa ser executado como root"
        exit 1
    fi
}

create_directories() {
    mkdir -p "$LOG_DIR" "$CONFIG_DIR" "$PID_DIR"
}

# ============================================================================
# DETECÇÃO E CONFIGURAÇÃO DE MODEMS
# ============================================================================

detect_all_modems() {
    log_info "Detectando modems (máximo: $MAX_MODEMS)..."
    
    # Limpar arrays
    DETECTED_MODEMS=()
    DETECTED_INTERFACES=()
    DETECTED_IPS=()
    DETECTED_GATEWAYS=()
    DETECTED_PREFIXES=()
    DETECTED_PORTS=()
    
    # Listar todos os modems
    local MODEM_LIST=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]\+" | cut -d'/' -f2 | sort -n)
    
    if [ -z "$MODEM_LIST" ]; then
        log_error "Nenhum modem detectado pelo ModemManager"
        return 1
    fi
    
    local total_modems=$(echo "$MODEM_LIST" | wc -l)
    log_info "Total de modems detectados: $total_modems"
    
    local port_counter=1
    local processed=0
    
    for MODEM_ID in $MODEM_LIST; do
        if [ $port_counter -gt $MAX_MODEMS ]; then
            log_warning "Limite de $MAX_MODEMS modems atingido"
            break
        fi
        
        log_info "Processando modem $MODEM_ID (${port_counter}/${MAX_MODEMS})..."
        
        # Desconectar primeiro (garantir estado limpo)
        mmcli -m $MODEM_ID --simple-disconnect 2>/dev/null || true
        sleep 2
        
        # Conectar modem
        log_info "  Conectando..."
        if ! mmcli -m $MODEM_ID --simple-connect="apn=$APN,user=$USER,password=$PASS,ip-type=ipv4" 2>/dev/null; then
            log_error "  Falha ao conectar modem $MODEM_ID"
            continue
        fi
        
        sleep 8
        
        # Obter bearer
        local BEARER=$(mmcli -m $MODEM_ID 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        
        if [ -z "$BEARER" ]; then
            log_error "  Modem $MODEM_ID: Bearer não encontrado"
            continue
        fi
        
        # Obter configurações de rede
        local IP=$(mmcli -b $BEARER 2>/dev/null | grep -w "address:" | awk '{print $3}')
        local GATEWAY=$(mmcli -b $BEARER 2>/dev/null | grep -w "gateway:" | awk '{print $3}')
        local PREFIX=$(mmcli -b $BEARER 2>/dev/null | grep -w "prefix:" | awk '{print $3}')
        local INTERFACE=$(mmcli -b $BEARER 2>/dev/null | grep -w "interface:" | awk '{print $3}')
        
        if [ -z "$IP" ] || [ -z "$INTERFACE" ] || [ -z "$GATEWAY" ]; then
            log_error "  Modem $MODEM_ID: Configuração incompleta (IP: $IP, IFACE: $INTERFACE, GW: $GATEWAY)"
            continue
        fi
        
        # Configurar interface de rede
        log_info "  Configurando interface $INTERFACE..."
        ip addr flush dev $INTERFACE 2>/dev/null || true
        ip addr add $IP/$PREFIX dev $INTERFACE 2>/dev/null || true
        ip link set $INTERFACE up 2>/dev/null || true
        
        # Testar conectividade
        log_info "  Testando conectividade..."
        if ! timeout 10 ping -I $INTERFACE -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log_error "  Modem $MODEM_ID: Sem conectividade"
            continue
        fi
        
        # Modem funcional - adicionar aos arrays
        local PROXY_PORT=$((BASE_PROXY_PORT + port_counter))
        local SOCKS_PORT=$((BASE_SOCKS_PORT + port_counter))
        
        DETECTED_MODEMS+=("$MODEM_ID")
        DETECTED_INTERFACES+=("$INTERFACE")
        DETECTED_IPS+=("$IP")
        DETECTED_GATEWAYS+=("$GATEWAY")
        DETECTED_PREFIXES+=("$PREFIX")
        DETECTED_PORTS+=("$PROXY_PORT")
        
        log_success "  Modem $MODEM_ID OK: $INTERFACE ($IP) → HTTP:$PROXY_PORT SOCKS:$SOCKS_PORT"
        
        port_counter=$((port_counter + 1))
        processed=$((processed + 1))
    done
    
    echo ""
    log_info "========================================="
    if [ ${#DETECTED_MODEMS[@]} -eq 0 ]; then
        log_error "Nenhum modem funcional detectado"
        return 1
    else
        log_success "Total de modems funcionais: ${#DETECTED_MODEMS[@]}"
        echo ""
        for i in "${!DETECTED_MODEMS[@]}"; do
            printf "   [%2d] Modem %-3s | %-6s | %-15s | HTTP:%-5d SOCKS:%-5d\n" \
                $((i+1)) \
                "${DETECTED_MODEMS[$i]}" \
                "${DETECTED_INTERFACES[$i]}" \
                "${DETECTED_IPS[$i]}" \
                "${DETECTED_PORTS[$i]}" \
                $((${DETECTED_PORTS[$i]} + 1000))
        done
        log_info "========================================="
        return 0
    fi
}

# ============================================================================
# CONFIGURAÇÃO DO SISTEMA
# ============================================================================

setup_routing() {
    log_info "Configurando roteamento..."
    
    # Habilitar IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Tornar permanente
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    # Limpar tabela de roteamento customizada
    cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.backup 2>/dev/null || true
    grep -v "^[0-9].*proxy_" /etc/iproute2/rt_tables 2>/dev/null > /tmp/rt_tables.tmp || true
    mv /tmp/rt_tables.tmp /etc/iproute2/rt_tables
    
    # Limpar regras antigas (priority 100-200)
    for PRIO in {100..200}; do
        ip rule del priority $PRIO 2>/dev/null || true
    done
    
    # Configurar roteamento para cada modem
    for i in "${!DETECTED_MODEMS[@]}"; do
        local IFACE="${DETECTED_INTERFACES[$i]}"
        local IP="${DETECTED_IPS[$i]}"
        local GATEWAY="${DETECTED_GATEWAYS[$i]}"
        local TABLE_ID=$((100 + i))
        local TABLE_NAME="proxy_${IFACE}"
        local METRIC=$((10 + i))
        
        # Adicionar tabela
        echo "$TABLE_ID $TABLE_NAME" >> /etc/iproute2/rt_tables
        
        # Limpar e criar rota padrão na tabela
        ip route flush table $TABLE_ID 2>/dev/null || true
        ip route add default via $GATEWAY dev $IFACE table $TABLE_ID
        
        # Rota padrão com métrica (fallback)
        ip route del default via $GATEWAY dev $IFACE 2>/dev/null || true
        ip route add default via $GATEWAY dev $IFACE metric $METRIC
        
        # Policy routing por IP de origem
        ip rule add from $IP table $TABLE_ID priority $((100 + i)) 2>/dev/null || true
        
        # NAT (MASQUERADE)
        iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
        
        # FORWARD rules
        iptables -A FORWARD -i $IFACE -j ACCEPT 2>/dev/null || true
        iptables -A FORWARD -o $IFACE -j ACCEPT 2>/dev/null || true
        
        log_success "  $IFACE → Tabela $TABLE_ID (Métrica $METRIC)"
    done
    
    # Flush cache
    ip route flush cache 2>/dev/null || true
}

create_proxy_config() {
    local INDEX=$1
    local MODEM_ID="${DETECTED_MODEMS[$INDEX]}"
    local IFACE="${DETECTED_INTERFACES[$INDEX]}"
    local IP="${DETECTED_IPS[$INDEX]}"
    local PROXY_PORT="${DETECTED_PORTS[$INDEX]}"
    local SOCKS_PORT=$((PROXY_PORT + 1000))
    
    local CONFIG_FILE="${CONFIG_DIR}/3proxy_${PROXY_PORT}.cfg"
    local PID_FILE="${PID_DIR}/3proxy_${PROXY_PORT}.pid"
    local LOG_FILE="${LOG_DIR}/3proxy_${PROXY_PORT}.log"
    
    cat > "$CONFIG_FILE" << EOF
# Configuração 3proxy - Modem ${MODEM_ID}
# Interface: ${IFACE}
# IP: ${IP}
# Gerado em: $(date)

daemon
pidfile ${PID_FILE}
log ${LOG_FILE} D
rotate 30
auth none
allow *

# Proxies
proxy -p${PROXY_PORT} -e${IP}
socks -p${SOCKS_PORT} -e${IP}
EOF
    
    log_success "  Config criado: $CONFIG_FILE"
}

start_proxy_instance() {
    local PROXY_PORT=$1
    local CONFIG_FILE="${CONFIG_DIR}/3proxy_${PROXY_PORT}.cfg"
    local PID_FILE="${PID_DIR}/3proxy_${PROXY_PORT}.pid"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config não encontrado: $CONFIG_FILE"
        return 1
    fi
    
    # Parar instância se estiver rodando
    if [ -f "$PID_FILE" ]; then
        local OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi
    fi
    
    # Iniciar nova instância
    /usr/local/bin/3proxy "$CONFIG_FILE"
    
    sleep 1
    
    # Verificar se iniciou
    if [ -f "$PID_FILE" ]; then
        local NEW_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$NEW_PID" ] && kill -0 "$NEW_PID" 2>/dev/null; then
            log_success "  3proxy iniciado: porta $PROXY_PORT (PID: $NEW_PID)"
            return 0
        fi
    fi
    
    log_error "  Falha ao iniciar 3proxy na porta $PROXY_PORT"
    return 1
}

setup_all_proxies() {
    log_info "Configurando instâncias do 3proxy..."
    
    local success_count=0
    
    for i in "${!DETECTED_PORTS[@]}"; do
        local PROXY_PORT="${DETECTED_PORTS[$i]}"
        
        create_proxy_config "$i"
        
        if start_proxy_instance "$PROXY_PORT"; then
            success_count=$((success_count + 1))
        fi
    done
    
    echo ""
    log_info "========================================="
    log_success "Instâncias 3proxy iniciadas: $success_count/${#DETECTED_PORTS[@]}"
    log_info "========================================="
}

save_status() {
    log_info "Salvando status do sistema..."
    
    local json="{"
    json+="\"timestamp\":\"$(date -Iseconds)\","
    json+="\"modem_count\":${#DETECTED_MODEMS[@]},"
    json+="\"modems\":["
    
    for i in "${!DETECTED_MODEMS[@]}"; do
        [ $i -gt 0 ] && json+=","
        json+="{"
        json+="\"id\":\"${DETECTED_MODEMS[$i]}\","
        json+="\"interface\":\"${DETECTED_INTERFACES[$i]}\","
        json+="\"ip\":\"${DETECTED_IPS[$i]}\","
        json+="\"gateway\":\"${DETECTED_GATEWAYS[$i]}\","
        json+="\"http_port\":${DETECTED_PORTS[$i]},"
        json+="\"socks_port\":$((${DETECTED_PORTS[$i]} + 1000))"
        json+="}"
    done
    
    json+="]}"
    
    echo "$json" > "$STATUS_FILE"
    chmod 644 "$STATUS_FILE"
}

# ============================================================================
# RENOVAÇÃO DE IP POR PORTA
# ============================================================================

find_modem_by_port() {
    local TARGET_PORT=$1
    
    for i in "${!DETECTED_PORTS[@]}"; do
        if [ "${DETECTED_PORTS[$i]}" -eq "$TARGET_PORT" ]; then
            echo "$i"
            return 0
        fi
    done
    
    return 1
}

renew_ip_by_port() {
    local TARGET_PORT=$1
    
    if [ -z "$TARGET_PORT" ]; then
        log_error "Porta não especificada"
        return 1
    fi
    
    log_info "========================================="
    log_info "Renovando IP da porta $TARGET_PORT"
    log_info "========================================="
    
    # Buscar índice do modem
    local MODEM_INDEX
    if ! MODEM_INDEX=$(find_modem_by_port "$TARGET_PORT"); then
        log_error "Porta $TARGET_PORT não encontrada no sistema"
        return 1
    fi
    
    local MODEM_ID="${DETECTED_MODEMS[$MODEM_INDEX]}"
    local OLD_IFACE="${DETECTED_INTERFACES[$MODEM_INDEX]}"
    local OLD_IP="${DETECTED_IPS[$MODEM_INDEX]}"
    local GATEWAY="${DETECTED_GATEWAYS[$MODEM_INDEX]}"
    local PREFIX="${DETECTED_PREFIXES[$MODEM_INDEX]}"
    local SOCKS_PORT=$((TARGET_PORT + 1000))
    
    log_info "Modem ID: $MODEM_ID"
    log_info "Interface atual: $OLD_IFACE"
    log_info "IP atual: $OLD_IP"
    
    # Obter IP público atual
    log_info "Obtendo IP público atual..."
    local OLD_PUBLIC_IP=$(timeout 10 curl -s --interface "$OLD_IFACE" https://api.ipify.org 2>/dev/null || echo "N/A")
    log_info "IP público atual: $OLD_PUBLIC_IP"
    
    # Processo de renovação
    local MAX_ATTEMPTS=3
    local ATTEMPT=1
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo ""
        log_info "Tentativa $ATTEMPT de $MAX_ATTEMPTS"
        log_info "-----------------------------------"
        
        # 1. Desconectar modem
        log_info "Desconectando modem..."
        mmcli -m "$MODEM_ID" --simple-disconnect 2>/dev/null || true
        
        # 2. Modo low power (força reset)
        log_info "Forçando reset de sessão..."
        mmcli -m "$MODEM_ID" --set-power-state-low 2>/dev/null || true
        sleep 5
        
        # 3. Aguardar liberação do IP
        log_info "Aguardando liberação do IP (20s)..."
        sleep 20
        
        # 4. Modo online
        log_info "Reativando modem..."
        mmcli -m "$MODEM_ID" --set-power-state-on 2>/dev/null || true
        sleep 5
        
        # 5. Reconectar
        log_info "Reconectando..."
        if ! mmcli -m "$MODEM_ID" --simple-connect="apn=$APN,user=$USER,password=$PASS,ip-type=ipv4" 2>/dev/null; then
            log_error "Falha ao reconectar"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi
        
        sleep 10
        
        # 6. Obter novas configurações
        local BEARER=$(mmcli -m "$MODEM_ID" 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
        
        if [ -z "$BEARER" ]; then
            log_error "Bearer não encontrado"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi
        
        local NEW_IP=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "address:" | awk '{print $3}')
        local NEW_GATEWAY=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "gateway:" | awk '{print $3}')
        local NEW_PREFIX=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "prefix:" | awk '{print $3}')
        local NEW_IFACE=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "interface:" | awk '{print $3}')
        
        if [ -z "$NEW_IP" ] || [ -z "$NEW_IFACE" ]; then
            log_error "Configuração incompleta obtida"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi
        
        log_info "Nova configuração: $NEW_IFACE ($NEW_IP)"
        
        # 7. Configurar interface
        log_info "Configurando interface..."
        ip addr flush dev "$NEW_IFACE" 2>/dev/null || true
        ip addr add "$NEW_IP/$NEW_PREFIX" dev "$NEW_IFACE"
        ip link set "$NEW_IFACE" up
        
        # 8. Reconfigurar roteamento
        log_info "Reconfigurando roteamento..."
        local TABLE_ID=$((100 + MODEM_INDEX))
        local METRIC=$((10 + MODEM_INDEX))
        
        # Rota padrão
        ip route del default via "$NEW_GATEWAY" dev "$NEW_IFACE" 2>/dev/null || true
        ip route add default via "$NEW_GATEWAY" dev "$NEW_IFACE" metric "$METRIC"
        
        # Tabela específica
        ip route flush table "$TABLE_ID" 2>/dev/null || true
        ip route add default via "$NEW_GATEWAY" dev "$NEW_IFACE" table "$TABLE_ID"
        
        # Policy routing
        ip rule del from "$OLD_IP" table "$TABLE_ID" 2>/dev/null || true
        ip rule add from "$NEW_IP" table "$TABLE_ID" priority $((100 + MODEM_INDEX))
        
        # NAT
        iptables -t nat -D POSTROUTING -o "$OLD_IFACE" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -A POSTROUTING -o "$NEW_IFACE" -j MASQUERADE
        
        # Flush cache
        ip route flush cache 2>/dev/null || true
        
        # 9. Testar conectividade
        log_info "Testando conectividade..."
        if ! timeout 10 ping -I "$NEW_IFACE" -c 2 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log_error "Sem conectividade"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi
        
        log_success "Conectividade OK"
        
        # 10. Reconfigurar 3proxy APENAS desta porta
        log_info "Reconfigurando 3proxy..."
        
        # Atualizar config
        local CONFIG_FILE="${CONFIG_DIR}/3proxy_${TARGET_PORT}.cfg"
        local PID_FILE="${PID_DIR}/3proxy_${TARGET_PORT}.pid"
        local LOG_FILE="${LOG_DIR}/3proxy_${TARGET_PORT}.log"
        
        cat > "$CONFIG_FILE" << EOF
# Configuração 3proxy - Modem ${MODEM_ID}
# Interface: ${NEW_IFACE}
# IP: ${NEW_IP}
# Atualizado em: $(date)

daemon
pidfile ${PID_FILE}
log ${LOG_FILE} D
rotate 30
auth none
allow *

# Proxies
proxy -p${TARGET_PORT} -e${NEW_IP}
socks -p${SOCKS_PORT} -e${NEW_IP}
EOF
        
        # Reiniciar APENAS esta instância
        if [ -f "$PID_FILE" ]; then
            local OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$OLD_PID" ]; then
                kill "$OLD_PID" 2>/dev/null || true
                sleep 1
            fi
        fi
        
        /usr/local/bin/3proxy "$CONFIG_FILE"
        sleep 2
        
        # 11. Obter novo IP público
        log_info "Obtendo novo IP público..."
        local NEW_PUBLIC_IP=$(timeout 10 curl -s --interface "$NEW_IFACE" https://api.ipify.org 2>/dev/null || echo "N/A")
        
        if [ -z "$NEW_PUBLIC_IP" ] || [ "$NEW_PUBLIC_IP" == "N/A" ]; then
            log_warning "Não foi possível obter IP público"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        fi
        
        log_info "Novo IP público: $NEW_PUBLIC_IP"
        
        # 12. Atualizar arrays globais
        DETECTED_IPS[$MODEM_INDEX]="$NEW_IP"
        DETECTED_INTERFACES[$MODEM_INDEX]="$NEW_IFACE"
        DETECTED_GATEWAYS[$MODEM_INDEX]="$NEW_GATEWAY"
        DETECTED_PREFIXES[$MODEM_INDEX]="$NEW_PREFIX"
        
        # Salvar novo status
        save_status
        
        # Verificar se IP mudou
        echo ""
        log_info "========================================="
        if [ "$NEW_PUBLIC_IP" != "$OLD_PUBLIC_IP" ] && [ "$OLD_PUBLIC_IP" != "N/A" ]; then
            log_success "IP RENOVADO COM SUCESSO!"
        else
            log_warning "IP NÃO MUDOU (operadora pode ter mantido)"
        fi
        log_info "========================================="
        echo "Porta HTTP:    $TARGET_PORT"
        echo "Porta SOCKS5:  $SOCKS_PORT"
        echo "Modem:         $MODEM_ID"
        echo "Interface:     $OLD_IFACE → $NEW_IFACE"
        echo "IP interno:    $OLD_IP → $NEW_IP"
        echo "IP público:    $OLD_PUBLIC_IP → $NEW_PUBLIC_IP"
        log_info "========================================="
        
        return 0
    done
    
    # Se chegou aqui, todas as tentativas falharam
    echo ""
    log_info "========================================="
    log_error "FALHA AO RENOVAR IP"
    log_info "========================================="
    echo "Tentativas: $MAX_ATTEMPTS"
    echo "Porta: $TARGET_PORT"
    echo ""
    echo "Possíveis causas:"
    echo "- Operadora mantém IP por período mínimo"
    echo "- CGNAT com pool limitado"
    echo "- Necessário aguardar mais tempo"
    log_info "========================================="
    
    return 1
}

# ============================================================================
# STATUS DO SISTEMA
# ============================================================================

show_status() {
    echo ""
    log_info "========================================="
    log_info "STATUS DO SISTEMA"
    log_info "========================================="
    echo ""
    
    # Modems
    echo "📱 MODEMS DETECTADOS:"
    local MODEM_LIST=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]\+" | cut -d'/' -f2 | sort -n)
    
    if [ -z "$MODEM_LIST" ]; then
        echo "  Nenhum modem detectado"
    else
        for MODEM_ID in $MODEM_LIST; do
            local STATE=$(mmcli -m "$MODEM_ID" 2>/dev/null | grep -oP "state: \K.*" | head -1 || echo "unknown")
            local SIGNAL=$(mmcli -m "$MODEM_ID" 2>/dev/null | grep -oP "signal quality: \K[0-9]+" || echo "N/A")
            
            local BEARER=$(mmcli -m "$MODEM_ID" 2>/dev/null | grep "Bearer.*paths" | tail -1 | awk -F'/' '{print $NF}')
            local IFACE="N/A"
            local IP="N/A"
            
            if [ -n "$BEARER" ]; then
                IFACE=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "interface:" | awk '{print $3}' || echo "N/A")
                IP=$(mmcli -b "$BEARER" 2>/dev/null | grep -w "address:" | awk '{print $3}' || echo "N/A")
            fi
            
            printf "  [%2s] Estado: %-12s | Sinal: %3s%% | Interface: %-6s | IP: %s\n" \
                "$MODEM_ID" "$STATE" "$SIGNAL" "$IFACE" "$IP"
        done
    fi
    
    echo ""
    echo "🔧 INSTÂNCIAS 3PROXY:"
    
    local proxy_count=0
    for PORT in $(seq $((BASE_PROXY_PORT + 1)) $((BASE_PROXY_PORT + MAX_MODEMS))); do
        local PID_FILE="${PID_DIR}/3proxy_${PORT}.pid"
        
        if [ -f "$PID_FILE" ]; then
            local PID=$(cat "$PID_FILE" 2>/dev/null)
            
            if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                # Buscar IP da config
                local CONFIG_FILE="${CONFIG_DIR}/3proxy_${PORT}.cfg"
                local PROXY_IP="N/A"
                
                if [ -f "$CONFIG_FILE" ]; then
                    PROXY_IP=$(grep -oP "proxy.*-e\K[0-9.]+" "$CONFIG_FILE" 2>/dev/null || echo "N/A")
                fi
                
                # Tentar obter IP público
                local PUBLIC_IP=$(timeout 5 curl -s -x "http://127.0.0.1:${PORT}" https://api.ipify.org 2>/dev/null || echo "N/A")
                
                printf "  HTTP:%-5d SOCKS:%-5d | IP interno: %-15s | IP público: %s | PID: %s\n" \
                    "$PORT" "$((PORT + 1000))" "$PROXY_IP" "$PUBLIC_IP" "$PID"
                
                proxy_count=$((proxy_count + 1))
            fi
        fi
    done
    
    if [ $proxy_count -eq 0 ]; then
        echo "  Nenhuma instância rodando"
    fi
    
    echo ""
    echo "💾 STATUS FILE: $STATUS_FILE"
    if [ -f "$STATUS_FILE" ]; then
        echo "  Última atualização: $(stat -c %y "$STATUS_FILE" 2>/dev/null | cut -d. -f1)"
    else
        echo "  Arquivo não encontrado"
    fi
    
    echo ""
    log_info "========================================="
}

# ============================================================================
# PARAR SISTEMA
# ============================================================================

stop_system() {
    log_info "Parando sistema..."
    
    # Parar todas as instâncias do 3proxy
    log_info "Parando instâncias 3proxy..."
    local stopped=0
    
    for PORT in $(seq $((BASE_PROXY_PORT + 1)) $((BASE_PROXY_PORT + MAX_MODEMS))); do
        local PID_FILE="${PID_DIR}/3proxy_${PORT}.pid"
        
        if [ -f "$PID_FILE" ]; then
            local PID=$(cat "$PID_FILE" 2>/dev/null)
            
            if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                kill "$PID" 2>/dev/null || true
                rm -f "$PID_FILE"
                stopped=$((stopped + 1))
            fi
        fi
    done
    
    # Fallback: killall
    killall 3proxy 2>/dev/null || true
    
    log_success "Instâncias 3proxy paradas: $stopped"
    
    # Desconectar modems
    log_info "Desconectando modems..."
    local MODEM_LIST=$(mmcli -L 2>/dev/null | grep -o "Modem/[0-9]\+" | cut -d'/' -f2)
    
    for MODEM_ID in $MODEM_LIST; do
        mmcli -m "$MODEM_ID" --simple-disconnect 2>/dev/null || true
    done
    
    log_success "Sistema parado"
}

# ============================================================================
# INICIAR SISTEMA
# ============================================================================

start_system() {
    check_root
    create_directories
    
    echo ""
    log_info "========================================="
    log_info "INICIANDO SISTEMA MULTI-MODEM"
    log_info "========================================="
    echo ""
    
    # Detectar modems
    if ! detect_all_modems; then
        log_error "Falha ao detectar modems"
        return 1
    fi
    
    echo ""
    
    # Configurar roteamento
    setup_routing
    
    echo ""
    
    # Configurar proxies
    setup_all_proxies
    
    echo ""
    
    # Salvar status
    save_status
    
    echo ""
    log_info "========================================="
    log_success "SISTEMA INICIADO COM SUCESSO!"
    log_info "========================================="
    echo ""
    echo "📊 RESUMO:"
    echo "  Modems funcionais: ${#DETECTED_MODEMS[@]}"
    echo "  Portas HTTP: $((BASE_PROXY_PORT + 1)) - $((BASE_PROXY_PORT + ${#DETECTED_MODEMS[@]}))"
    echo "  Portas SOCKS5: $((BASE_SOCKS_PORT + 1)) - $((BASE_SOCKS_PORT + ${#DETECTED_MODEMS[@]}))"
    echo ""
    echo "🌐 API Dashboard: http://SEU_IP:5000"
    echo ""
    log_info "========================================="
}

# ============================================================================
# REINICIAR SISTEMA
# ============================================================================

restart_system() {
    stop_system
    sleep 3
    start_system
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        start)
            start_system
            ;;
        stop)
            check_root
            stop_system
            ;;
        restart)
            check_root
            restart_system
            ;;
        status)
            show_status
            ;;
        renew-port)
            check_root
            if [ -z "${2:-}" ]; then
                log_error "Uso: $0 renew-port <PORTA>"
                log_error "Exemplo: $0 renew-port 6001"
                exit 1
            fi
            renew_ip_by_port "$2"
            ;;
        *)
            echo "Uso: $0 {start|stop|restart|status|renew-port PORT}"
            echo ""
            echo "Comandos:"
            echo "  start           - Inicia o sistema"
            echo "  stop            - Para o sistema"
            echo "  restart         - Reinicia o sistema completo"
            echo "  status          - Mostra status detalhado"
            echo "  renew-port PORT - Renova IP de porta específica"
            echo ""
            echo "Exemplos:"
            echo "  $0 start"
            echo "  $0 renew-port 6001"
            echo "  $0 status"
            exit 1
            ;;
    esac
}

main "$@"