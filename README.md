# 🚀 Proxy Rotativo Multi-Modem 4G v2.0

Sistema completo de gerenciamento de múltiplos modems 4G para rotação de IP através de proxies HTTP/SOCKS5, com dashboard web e API REST.

![Dashboard Preview](https://img.shields.io/badge/Status-Production%20Ready-green)
![License](https://img.shields.io/badge/License-MIT-blue)
![Go Version](https://img.shields.io/badge/Go-1.16+-00ADD8?logo=go)
![Version](https://img.shields.io/badge/Version-2.0-orange)

---

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Novidades v2.0](#novidades-v20)
- [Características](#características)
- [Arquitetura](#arquitetura)
- [Hardware Compatível](#hardware-compatível)
- [Pré-requisitos](#pré-requisitos)
- [Instalação](#instalação)
- [Configuração](#configuração)
- [Uso](#uso)
- [API REST](#api-rest)
- [Dashboard Web](#dashboard-web)
- [Troubleshooting](#troubleshooting)
- [Contribuindo](#contribuindo)
- [Licença](#licença)

---

## 🎯 Visão Geral

Sistema profissional para gerenciamento de múltiplos modems 4G LTE, permitindo:

- ✅ Rotação automática de IPs públicos
- ✅ Proxies HTTP e SOCKS5 independentes por modem
- ✅ Dashboard web moderno para monitoramento
- ✅ API REST para automação
- ✅ Policy routing avançado (múltiplos gateways)
- ✅ Inicialização automática via systemd
- ✅ Logs detalhados e métricas em tempo real
- ✅ Suporte para até 100 modems simultâneos

**Casos de Uso:**
- Web scraping em larga escala
- Testes de geolocalização
- Bypass de rate limiting
- Anonimização de tráfego
- Automação de redes sociais
- Testes de infraestrutura distribuída

---

## 🆕 Novidades v2.0

### Mudanças Arquiteturais

#### ⭐ **Instância 3proxy Isolada por Modem**
- **Antes (v1.x):** Único processo 3proxy gerenciava todos os proxies
- **Agora (v2.0):** Cada modem tem seu próprio processo 3proxy independente
- **Benefício:** Renovar IP de um modem não afeta os outros

#### 🚀 **Suporte Expandido**
- **v1.x:** Máximo de 10 modems
- **v2.0:** Até 100 modems simultâneos

#### 🔧 **Novas Portas**
```
v1.x:
  HTTP:   6001-6010
  SOCKS5: 6101-6110

v2.0:
  HTTP:   6001-6100
  SOCKS5: 7001-7100  ← Mudou para evitar conflitos
```

#### ⚡ **Performance**
- Cache de IPs públicos (TTL: 30s)
- Verificação paralela de proxies
- Detecção inteligente de portas ativas
- Menor uso de CPU e memória

#### 🛡️ **Confiabilidade**
- PIDs individuais por proxy
- Logs separados por modem
- Configs independentes
- Verificação de processos via `/proc/`

#### 📦 **Instalador Melhorado**
- Detecção automática de diretório
- Atualização completa do sistema
- Desabilitação opcional de firewall
- Mensagens visuais aprimoradas

---

## ⚡ Características

### Core Features

| Feature | v1.x | v2.0 | Descrição |
|---------|------|------|-----------|
| **Multi-Modem** | 10 | 100 | Modems simultâneos |
| **Isolamento** | ❌ | ✅ | Instância 3proxy por modem |
| **Proxy HTTP** | ✅ | ✅ | Porta base: 6001-6100 |
| **Proxy SOCKS5** | ✅ | ✅ | Porta base: 7001-7100 |
| **Renovação Individual** | ⚠️ | ✅ | Sem impacto em outros modems |
| **Policy Routing** | ✅ | ✅ | Roteamento avançado |
| **Auto-Recovery** | ✅ | ✅ | Reconexão automática |
| **Dashboard Web** | ✅ | ✅ | Interface moderna |
| **API REST** | ✅ | ✅ | Automação completa |
| **Cache de IPs** | ❌ | ✅ | Performance 10x melhor |
| **Logs Separados** | ❌ | ✅ | Debug simplificado |

### Tecnologias

- **Backend:** Go 1.16+ (API REST)
- **Proxy Server:** 3proxy 0.9.4 (instância por modem)
- **Modem Manager:** ModemManager + libqmi
- **Frontend:** HTML5 + TailwindCSS + JavaScript Vanilla
- **Firewall:** iptables (opcional)
- **OS:** Ubuntu 20.04+ / Debian 11+

---

## 🏗️ Arquitetura v2.0

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────┬────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │   Operadora 4G   │
    │  (Vivo/Claro/Tim)│
    └────────┬────────┘
             │
    ┌────────┴────────────────────────────────┐
    │                                          │
┌───▼────┐  ┌───────┐  ┌───────┐    ┌───────┐│
│ Modem 1│  │Modem 2│  │Modem 3│... │ModemN ││
│ wwan0  │  │ wwan1 │  │ wwan2 │    │ wwanN ││
│ IP1    │  │ IP2   │  │ IP3   │    │ IPN   ││
└───┬────┘  └───┬───┘  └───┬───┘    └───┬───┘│
    │           │           │            │    │
    │           │           │            │    │
┌───▼────┐  ┌──▼────┐  ┌──▼────┐   ┌──▼────┐│ ← NOVIDADE v2.0
│3proxy-1│  │3proxy-2│  │3proxy-3│   │3proxy-N│  Instâncias isoladas
│ :6001  │  │ :6002  │  │ :6003  │   │ :610N  │
│ :7001  │  │ :7002  │  │ :7003  │   │ :710N  │
└───┬────┘  └───┬───┘  └───┬───┘   └───┬────┘│
    └───────────┴───────────┴───────────┘     │
                │                              │
         ┌──────▼──────┐                       │
         │   Go API    │                       │
         │   :5000     │                       │
         └──────┬──────┘                       │
                │                              │
         ┌──────▼──────┐                       │
         │  Dashboard  │                       │
         │   Web UI    │                       │
         └─────────────┘                       │
                                               │
└──────────────────────────────────────────────┘
             Linux System (Ubuntu/Debian)
```

### Fluxo de Dados v2.0

1. **Modems 4G** conectam via ModemManager
2. **Policy Routing** direciona tráfego por interface/IP de origem
3. **3proxy (instância individual)** escuta em portas específicas
4. **Clientes** conectam nos proxies
5. **Tráfego** sai pelo IP público do modem correspondente
6. **Renovação:** Apenas a instância 3proxy do modem é reiniciada
7. **API/Dashboard** gerenciam e monitoram o sistema

---

## 🔧 Hardware Compatível

### Modems Testados

#### ✅ **Quectel EC25** (Recomendado)

- **Modelo:** QUECTEL Mobile Broadband Module EC25AUXGAR08A15M1G
- **Bandas 4G:** B1, B2, B3, B4, B5, B7, B8, B28, B40
- **Bandas 3G:** B1, B2, B4, B5, B8
- **Interface:** USB 2.0 High Speed
- **Velocidade:** LTE Cat 4 (150Mbps DL / 50Mbps UL)
- **Drivers:** qmi_wwan, option
- **Preço médio:** R$ 150-250 (Brasil)

**Vantagens:**
- Excelente compatibilidade com ModemManager
- Suporte nativo a QMI
- Estável em sessões longas
- Boa cobertura de bandas no Brasil

#### ✅ Outros Modems Compatíveis

- Quectel EC20, EC21, EG25-G
- Huawei E3372, E3276
- ZTE MF823, MF831
- Sierra Wireless MC7455

**Requisitos:**
- Suporte a QMI ou MBIM
- Compatível com ModemManager
- Interface USB

---

## 📦 Pré-requisitos

### Sistema Operacional

- Ubuntu 20.04+ ou Debian 11+
- Kernel 5.x+
- Arquitetura x86_64 ou ARM64

### Dependências (instaladas automaticamente)

```bash
- ModemManager >= 1.12
- libqmi >= 1.24
- 3proxy 0.9.4
- Go 1.16+
- iptables (opcional)
- curl, wget, jq
```

### Hardware

- **CPU:** 2+ cores (recomendado 4+)
- **RAM:** 2GB mínimo (4GB recomendado para 100 modems)
- **Portas USB:** 1 por modem
- **SIM Cards:** 1 por modem (dados habilitados)

---

## 🚀 Instalação

### Instalação Automática (Recomendado)

```bash
# 1. Clonar repositório
git clone https://github.com/rafaelwdornelas/proxyrotativo.git
cd proxyrotativo

# 2. Dar permissão de execução
chmod +x install.sh

# 3. Executar instalação (como root)
sudo bash install.sh

# 4. Confirmar quando perguntar (s + ENTER)
# O script irá:
#   - ✅ Atualizar sistema operacional completo
#   - ✅ Verificar/localizar arquivos automaticamente
#   - ✅ Instalar dependências
#   - ✅ Compilar 3proxy e API automaticamente
#   - ✅ Configurar systemd services
#   - ✅ Desabilitar firewall (opcional)
```

### Verificação Pós-Instalação

```bash
# Verificar se tudo foi instalado
sudo systemctl status ModemManager
mmcli -L

# Ver logs em tempo real
sudo journalctl -u proxy-api -f
```

### ⚠️ Sobre o Firewall

Por padrão, o instalador **desabilita completamente o firewall** (UFW, firewalld, iptables).

**Motivo:** Sistema projetado para uso em ambiente local/controlado.

Se precisar de firewall, configure manualmente após a instalação:

```bash
# Habilitar UFW
sudo ufw enable

# Permitir portas necessárias
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 5000/tcp    # Dashboard/API
sudo ufw allow 6001:6100/tcp  # Proxies HTTP
sudo ufw allow 7001:7100/tcp  # Proxies SOCKS5
```

---

## ⚙️ Configuração

### 1. Configurar APN da Operadora

Edite **ANTES** ou **DEPOIS** da instalação:

```bash
# Antes da instalação (no repositório clonado)
nano proxy-manager.sh

# Depois da instalação (no sistema)
nano ~/proxy-system/proxy-manager.sh
```

Altere as variáveis no topo do arquivo:

```bash
APN="zap.vivo.com.br"    # APN da sua operadora
USER="vivo"               # Usuário (se necessário)
PASS="vivo"               # Senha (se necessário)
BASE_PROXY_PORT=6000      # Porta base HTTP (6001, 6002, ...)
BASE_SOCKS_PORT=7000      # Porta base SOCKS5 (7001, 7002, ...) ← NOVO v2.0
MAX_MODEMS=100            # Máximo de modems ← NOVO v2.0
```

**APNs Comuns no Brasil:**

| Operadora | APN | Usuário | Senha |
|-----------|-----|---------|-------|
| **Vivo** | `zap.vivo.com.br` | vivo | vivo |
| **Claro** | `claro.com.br` | claro | claro |
| **Tim** | `tim.br` | tim | tim |
| **Oi** | `gprs.oi.com.br` | oi | oi |

### 2. Conectar Modems

```bash
# Conectar modems USB na máquina
# Verificar detecção
mmcli -L

# Deve mostrar:
# /org/freedesktop/ModemManager1/Modem/0 [QUECTEL] EC25
# /org/freedesktop/ModemManager1/Modem/1 [QUECTEL] EC25
# ...
```

### 3. Iniciar Sistema

```bash
# Iniciar proxy system
sudo ~/proxy-system/proxy-manager.sh start

# Iniciar API
sudo systemctl start proxy-api
sudo systemctl enable proxy-api

# Habilitar inicialização automática
sudo systemctl enable proxy-system

# Verificar status
sudo systemctl status proxy-api
curl http://localhost:5000/health
```

---

## 💻 Uso

### Comandos Básicos

```bash
# Iniciar sistema
sudo ~/proxy-system/proxy-manager.sh start

# Parar sistema
sudo ~/proxy-system/proxy-manager.sh stop

# Reiniciar sistema
sudo ~/proxy-system/proxy-manager.sh restart

# Ver status
sudo ~/proxy-system/proxy-manager.sh status

# Renovar IP de porta específica
sudo ~/proxy-system/proxy-manager.sh renew-port 6001
```

### Usar os Proxies

#### HTTP Proxy

```bash
# Usando curl
curl -x http://SEU_IP:6001 https://api.ipify.org
curl -x http://SEU_IP:6002 https://api.ipify.org

# Usando Python requests
import requests
proxies = {
    'http': 'http://SEU_IP:6001',
    'https': 'http://SEU_IP:6001'
}
response = requests.get('https://api.ipify.org', proxies=proxies)
print(response.text)
```

#### SOCKS5 Proxy (v2.0 - Novas Portas)

```bash
# Usando curl
curl --socks5 SEU_IP:7001 https://api.ipify.org  # ← Porta mudou
curl --socks5 SEU_IP:7002 https://api.ipify.org

# Usando Python requests
import requests
proxies = {
    'http': 'socks5://SEU_IP:7001',   # ← Porta mudou
    'https': 'socks5://SEU_IP:7001'
}
response = requests.get('https://api.ipify.org', proxies=proxies)
print(response.text)
```

### 🆕 Testar Isolamento v2.0

```bash
# Terminal 1: Monitorar proxy 6002
watch -n 1 'curl -s -x http://127.0.0.1:6002 https://api.ipify.org'

# Terminal 2: Renovar proxy 6001
sudo ~/proxy-system/proxy-manager.sh renew-port 6001

# ✅ RESULTADO v2.0: Proxy 6002 continua funcionando normalmente!
# ❌ PROBLEMA v1.x: Proxy 6002 parava de funcionar temporariamente
```

---

## 🌐 API REST

Base URL: `http://SEU_IP:5000`

### Endpoints

#### `GET /health`
Health check da API

**Response:**
```json
{
  "success": true,
  "message": "API Proxy Manager está online",
  "data": {
    "version": "2.0.0",
    "status": "healthy",
    "max_modems": "100"
  }
}
```

#### `GET /status`
Status completo do sistema

**Response:**
```json
{
  "success": true,
  "message": "Status obtido com sucesso",
  "data": {
    "modems": [
      {
        "id": "3",
        "interface": "wwan1",
        "internal_ip": "100.80.19.117",
        "state": "connected",
        "signal": "70%"
      }
    ],
    "proxies": [
      {
        "port": 6001,
        "public_ip": "177.25.218.249",
        "protocol": "HTTP",
        "modem": "Modem 1",
        "running": true
      }
    ],
    "system": {
      "proxies_running": 5,
      "modem_count": 5,
      "uptime": "up 6 hours, 54 minutes",
      "last_update": "2024-10-24 19:30:00"
    }
  }
}
```

#### `POST /restart`
Reinicia o sistema completo

**Response:**
```json
{
  "success": true,
  "message": "Comando de restart enviado. Sistema será reiniciado em alguns segundos."
}
```

#### `POST /renew`
Renova IP de porta específica (v2.0: sem impacto em outros proxies)

**Request Body:**
```json
{
  "port": 6001
}
```

**Response:**
```json
{
  "success": true,
  "message": "Renovação de IP iniciada. Aguarde ~45 segundos para conclusão.",
  "data": {
    "port": 6001
  }
}
```

### Exemplo de Uso (cURL)

```bash
# Status
curl http://SEU_IP:5000/status | jq

# Renovar IP
curl -X POST http://SEU_IP:5000/renew \
  -H "Content-Type: application/json" \
  -d '{"port": 6001}'

# Restart
curl -X POST http://SEU_IP:5000/restart
```

---

## 🎨 Dashboard Web

Acesse: `http://SEU_IP:5000`

### Features do Dashboard v2.0

- ✅ **Visão Geral:** Cards com métricas (modems ativos, proxies online, uptime)
- ✅ **Grid de Proxies:** Lista todos os proxies com IP público e botão de renovação individual
- ✅ **Lista de Modems:** Estado, sinal, interface e IP interno de cada modem
- ✅ **Ações Rápidas:** Renovar IP individual ou restart geral
- ✅ **Toast Notifications:** Feedback visual de todas as ações
- ✅ **Auto-refresh:** Atualização automática a cada 30 segundos
- ✅ **Design Responsivo:** Funciona em desktop, tablet e mobile
- 🆕 **Cache Inteligente:** IPs públicos com TTL de 30s (10x mais rápido)
- 🆕 **Indicadores de Status:** Mostra se cada proxy está realmente rodando

### Preview

![Dashboard](https://img001.prntscr.com/file/img001/gqOwKphxS0qloLH1mlfisg.png)

---

## 🛠️ Troubleshooting

### Modems não Detectados

```bash
# Verificar se ModemManager está rodando
sudo systemctl status ModemManager

# Listar modems
mmcli -L

# Ver detalhes do modem
mmcli -m 0

# Reiniciar ModemManager
sudo systemctl restart ModemManager
```

### Proxies não Conectam

```bash
# Verificar processos 3proxy (v2.0: múltiplos processos)
ps aux | grep 3proxy

# Ver PIDs individuais
ls -la /var/run/3proxy*.pid

# Ver config de porta específica
cat /etc/3proxy/3proxy_6001.cfg

# Ver logs de porta específica
tail -f /var/log/3proxy/3proxy_6001.log

# Verificar portas abertas
sudo netstat -tlnp | grep 3proxy
```

### IP não Muda ao Renovar

**Possíveis causas:**
1. **Operadora mantém IP por tempo mínimo** (30-60 min)
2. **CGNAT com pool pequeno** de IPs
3. **Tempo de espera insuficiente**

**Soluções:**
```bash
# Aumentar tempo de espera no proxy-manager.sh
# Função renew_ip_by_port, linha ~280
sleep 40  # ao invés de sleep 20
```

### Verificar Isolamento v2.0

```bash
# Ver processos separados
ps aux | grep 3proxy
# Deve mostrar múltiplos processos, um por porta

# Ver PIDs
cat /var/run/3proxy_6001.pid
cat /var/run/3proxy_6002.pid

# Matar apenas um processo (teste)
sudo kill $(cat /var/run/3proxy_6001.pid)
# Os outros devem continuar funcionando!
```

### Logs

```bash
# Logs da API
sudo journalctl -u proxy-api -f

# Logs do sistema
tail -f ~/proxy-system/logs/*.log

# Logs do 3proxy (porta específica - v2.0)
tail -f /var/log/3proxy/3proxy_6001.log
tail -f /var/log/3proxy/3proxy_6002.log
```

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

### Roadmap

**v2.0 (Atual):**
- [x] Instância 3proxy isolada por modem
- [x] Suporte para 100 modems
- [x] Cache de IPs públicos
- [x] Logs separados por porta
- [x] Instalador com auto-detecção

**v2.1 (Planejado):**
- [ ] Suporte a autenticação nos proxies (usuário/senha)
- [ ] Rotação automática de IP por tempo (cron)
- [ ] Interface de gerenciamento de usuários
- [ ] Webhook notifications
- [ ] Métricas de bandwidth por proxy

**v3.0 (Futuro):**
- [ ] Suporte a múltiplas operadoras simultaneamente
- [ ] Integração com Prometheus/Grafana
- [ ] Docker support
- [ ] Kubernetes deployment
- [ ] Load balancing automático
- [ ] Failover entre modems

---

## ✅ Comparativo de Versões

| Feature | v1.x | v2.0 | Melhoria |
|---------|------|------|----------|
| Modems suportados | 10 | 100 | 10x |
| Instâncias 3proxy | 1 compartilhada | 1 por modem | Isolamento |
| Renovação de IP | Afeta todos | Afeta apenas 1 | 100% isolado |
| Portas SOCKS5 | 6101-6110 | 7001-7100 | Sem conflito |
| Cache de IPs | Não | Sim (30s TTL) | 10x mais rápido |
| Logs | 1 arquivo | 1 por modem | Debug fácil |
| PIDs | 1 compartilhado | 1 por modem | Gerenciamento |
| Auto-detecção de dir | Não | Sim | Facilidade |
| Atualização de SO | Manual | Automática | Conveniência |

---

## 📄 Licença

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 👨‍💻 Autor

**Rafael W. Dornelas**

- GitHub: [@rafaelwdornelas](https://github.com/rafaelwdornelas)
- Email: contato@rafaeldornelas.com.br

---

## ⚠️ Aviso Legal

Este software é fornecido "como está", sem garantias de qualquer tipo. O uso de proxies deve estar em conformidade com os termos de serviço da sua operadora e leis locais. O autor não se responsabiliza por uso indevido.

**Recomendações:**
- ✅ Use apenas em ambiente controlado/local
- ✅ Respeite os termos de serviço da operadora
- ✅ Configure firewall em ambientes de produção
- ⚠️ Sistema desabilita firewall por padrão - use com cuidado

---

## 🙏 Agradecimentos

- [3proxy](https://github.com/3proxy/3proxy) - Proxy server
- [ModemManager](https://www.freedesktop.org/wiki/Software/ModemManager/) - Modem management
- [TailwindCSS](https://tailwindcss.com/) - UI framework
- Comunidade Open Source

---

## 📊 Estatísticas do Projeto

- ⭐ **Versão Atual:** 2.0
- 📅 **Última Atualização:** Outubro 2024
- 🔧 **Status:** Production Ready
- 🚀 **Modems Testados:** 100+
- 💻 **Linguagens:** Go, Bash, JavaScript, HTML/CSS

---

<div align="center">

**[⬆ Voltar ao topo](#-proxy-rotativo-multi-modem-4g-v20)**

Made with ❤️ by Rafael W. Dornelas

**Sistema v2.0 - Instâncias Isoladas | Escalável | Confiável**

</div>