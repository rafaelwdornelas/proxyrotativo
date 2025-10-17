# 🚀 Proxy Rotativo Multi-Modem 4G

Sistema completo de gerenciamento de múltiplos modems 4G para rotação de IP através de proxies HTTP/SOCKS5, com dashboard web e API REST.

![Dashboard Preview](https://img.shields.io/badge/Status-Production%20Ready-green)
![License](https://img.shields.io/badge/License-MIT-blue)
![Go Version](https://img.shields.io/badge/Go-1.16+-00ADD8?logo=go)

---

## 📋 Índice

- [Visão Geral](#visão-geral)
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

**Casos de Uso:**
- Web scraping em larga escala
- Testes de geolocalização
- Bypass de rate limiting
- Anonimização de tráfego
- Automação de redes sociais

---

## ⚡ Características

### Core Features

| Feature | Descrição |
|---------|-----------|
| **Multi-Modem** | Suporte para até 10 modems simultâneos |
| **Proxy HTTP/SOCKS5** | Cada modem gera 2 proxies (HTTP + SOCKS5) |
| **Renovação de IP** | Troca de IP por demanda (API ou Dashboard) |
| **Policy Routing** | Roteamento avançado por interface/marca de pacote |
| **Auto-Recovery** | Reconexão automática em caso de falha |
| **Dashboard Web** | Interface moderna com TailwindCSS |
| **API REST** | Automação completa via HTTP |
| **Systemd Integration** | Inicialização automática no boot |

### Tecnologias

- **Backend:** Go 1.16+ (API REST)
- **Proxy Server:** 3proxy 0.9.4
- **Modem Manager:** ModemManager + libqmi
- **Frontend:** HTML5 + TailwindCSS + JavaScript Vanilla
- **Firewall:** iptables + ufw
- **OS:** Ubuntu 20.04+ / Debian 11+

---

## 🏗️ Arquitetura

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
    ┌────────┴────────────────────────────────────┐
    │                                             │
┌───▼────┐  ┌───────┐  ┌───────┐       ┌───────┐  │
│ Modem 1│  │Modem 2│  │Modem 3│  ...  │ModemN │  │
│ wwan0  │  │ wwan1 │  │ wwan2 │       │ wwanN │  │
│ IP1    │  │ IP2   │  │ IP3   │       │ IPN   │  │
└───┬────┘  └───┬───┘  └───┬───┘       └───┬───┘  │
    │           │           │               │     │
    └───────────┴───────────┴───────────────┘     │
                │                                 │
         ┌──────▼──────┐                          │
         │  3proxy     │                          │
         │  :6001-6010 │ (HTTP)                   │
         │  :6101-6110 │ (SOCKS5)                 │
         └──────┬──────┘                          │
                │                                 │
         ┌──────▼──────┐                          │
         │   Go API    │                          │
         │   :5000     │                          │
         └──────┬──────┘                          │
                │                                 │
         ┌──────▼──────┐                          │
         │  Dashboard  │                          │
         │   Web UI    │                          │
         └─────────────┘                          │
                                                  │
└─────────────────────────────────────────────────┘
             Linux System (Ubuntu/Debian)
```

### Fluxo de Dados

1. **Modems 4G** conectam via ModemManager (APN, usuário, senha)
2. **Policy Routing** direciona tráfego por interface/marca
3. **3proxy** escuta em portas específicas (6001-6010, 6101-6110)
4. **Clientes** conectam nos proxies
5. **Tráfego** sai pelo IP público do modem correspondente
6. **API/Dashboard** gerenciam e monitoram o sistema

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

### Dependências

```bash
- ModemManager >= 1.12
- libqmi >= 1.24
- 3proxy 0.9.4
- Go 1.16+
- iptables
- curl, wget
```

### Hardware

- **CPU:** 2+ cores (recomendado 4+)
- **RAM:** 2GB mínimo (4GB recomendado)
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

# 4. Seguir instruções na tela
```

### Instalação Manual

<details>
<summary>Clique para ver passos manuais</summary>

```bash
# 1. Atualizar sistema
sudo apt update && sudo apt upgrade -y

# 2. Instalar dependências
sudo apt install -y modemmanager libqmi-utils libmbim-utils \
    usb-modeswitch build-essential golang-go git curl wget \
    net-tools iptables ufw iptables-persistent

# 3. Compilar 3proxy
cd /tmp
wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
tar -xzf 0.9.4.tar.gz
cd 3proxy-0.9.4
make -f Makefile.Linux
sudo cp bin/3proxy /usr/local/bin/
sudo chmod +x /usr/local/bin/3proxy

# 4. Criar diretórios
mkdir -p ~/proxy-system/{logs}
mkdir -p ~/proxy-api

# 5. Copiar arquivos
cp proxy-manager.sh ~/proxy-system/
cp main.go ~/proxy-api/
chmod +x ~/proxy-system/proxy-manager.sh

# 6. Compilar API
cd ~/proxy-api
go build -o proxy-api main.go

# 7. Configurar systemd
sudo cp systemd/proxy-api.service /etc/systemd/system/
sudo cp systemd/proxy-system.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable proxy-api proxy-system
```

</details>

---

## ⚙️ Configuração

### 1. Configurar APN da Operadora

Edite o arquivo `proxy-manager.sh`:

```bash
nano ~/proxy-system/proxy-manager.sh
```

Altere as variáveis no topo do arquivo:

```bash
APN="zap.vivo.com.br"    # APN da sua operadora
USER="vivo"               # Usuário (se necessário)
PASS="vivo"               # Senha (se necessário)
BASE_PROXY_PORT=6000      # Porta base HTTP (6001, 6002, ...)
BASE_SOCKS_PORT=6100      # Porta base SOCKS5 (6101, 6102, ...)
```

**APNs Comuns no Brasil:**

| Operadora | APN | Usuário | Senha |
|-----------|-----|---------|-------|
| **Vivo** | `zap.vivo.com.br` | vivo | vivo |
| **Claro** | `claro.com.br` | claro | claro |
| **Tim** | `tim.br` | tim | tim |
| **Oi** | `gprs.oi.com.br` | oi | oi |

### 2. Configurar Firewall

```bash
# Permitir portas
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 5000/tcp    # Dashboard/API
sudo ufw allow 6001:6010/tcp  # Proxies HTTP
sudo ufw allow 6101:6110/tcp  # Proxies SOCKS5
sudo ufw enable
```

### 3. Iniciar Sistema

```bash
# Iniciar proxy system
sudo ~/proxy-system/proxy-manager.sh start

# Iniciar API
sudo systemctl start proxy-api

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

#### SOCKS5 Proxy

```bash
# Usando curl
curl --socks5 SEU_IP:6101 https://api.ipify.org

# Usando Python requests
import requests
proxies = {
    'http': 'socks5://SEU_IP:6101',
    'https': 'socks5://SEU_IP:6101'
}
response = requests.get('https://api.ipify.org', proxies=proxies)
print(response.text)
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
    "version": "1.0.0",
    "status": "healthy"
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
        "modem": "Modem 1"
      }
    ],
    "system": {
      "proxy3_running": true,
      "modem_count": 2,
      "uptime": "up 6 hours, 54 minutes"
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
Renova IP de porta específica

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

### Features do Dashboard

- ✅ **Visão Geral:** Cards com métricas (modems ativos, proxies online, uptime)
- ✅ **Grid de Proxies:** Lista todos os proxies com IP público e botão de renovação
- ✅ **Lista de Modems:** Estado, sinal, interface e IP interno de cada modem
- ✅ **Ações Rápidas:** Renovar IP individual ou restart geral
- ✅ **Toast Notifications:** Feedback visual de todas as ações
- ✅ **Auto-refresh:** Atualização automática a cada 30 segundos
- ✅ **Design Responsivo:** Funciona em desktop, tablet e mobile

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
# Verificar se 3proxy está rodando
ps aux | grep 3proxy

# Ver config do 3proxy
cat /etc/3proxy/3proxy.cfg

# Ver logs
tail -f /var/log/3proxy/3proxy.log

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
# Linha ~280, mudar de 20s para 40s ou 60s
sleep 40  # ao invés de sleep 20
```

### Firewall Bloqueando

```bash
# Ver regras
sudo iptables -L -n -v

# Limpar regras (CUIDADO)
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Reconfigurar
sudo ~/proxy-system/proxy-manager.sh restart
```

### Logs

```bash
# Logs da API
sudo journalctl -u proxy-api -f

# Logs do sistema
tail -f ~/proxy-system/logs/*.log

# Logs do 3proxy
tail -f /var/log/3proxy/3proxy.log
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

- [ ] Suporte a autenticação nos proxies (usuário/senha)
- [ ] Rotação automática de IP por tempo
- [ ] Suporte a múltiplas operadoras simultaneamente
- [ ] Métricas de bandwidth por proxy
- [ ] Integração com Prometheus/Grafana
- [ ] Docker support
- [ ] Suporte a USSD commands
- [ ] Webhook notifications

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

---

## 🙏 Agradecimentos

- [3proxy](https://github.com/3proxy/3proxy) - Proxy server
- [ModemManager](https://www.freedesktop.org/wiki/Software/ModemManager/) - Modem management
- [TailwindCSS](https://tailwindcss.com/) - UI framework
- Comunidade Open Source

---

<div align="center">

**[⬆ Voltar ao topo](#-proxy-rotativo-multi-modem-4g)**

Made with ❤️ by Rafael W. Dornelas

</div>
```

Este README está completo e profissional, pronto para o GitHub! 🚀