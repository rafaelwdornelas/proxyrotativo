package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

var SCRIPT_PATH = func() string {
	home := os.Getenv("HOME")
	if home == "" {
		home = "/root"
	}
	path := home + "/proxy-system/proxy-manager.sh"
	log.Printf("Script path configurado: %s", path)
	return path
}()

const (
	PORT = ":5000"
)

// Response padrão
type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// Status completo
type StatusResponse struct {
	Modems  []ModemInfo `json:"modems"`
	Proxies []ProxyInfo `json:"proxies"`
	System  SystemInfo  `json:"system"`
}

type ModemInfo struct {
	ID         string `json:"id"`
	Interface  string `json:"interface"`
	InternalIP string `json:"internal_ip"`
	State      string `json:"state"`
	Signal     string `json:"signal"`
}

type ProxyInfo struct {
	Port     int    `json:"port"`
	PublicIP string `json:"public_ip"`
	Protocol string `json:"protocol"`
	Modem    string `json:"modem"`
}

type SystemInfo struct {
	Proxy3Running bool   `json:"proxy3_running"`
	ModemCount    int    `json:"modem_count"`
	Uptime        string `json:"uptime"`
}

type RenewRequest struct {
	Port int `json:"port"`
}

// Executar comando shell
func runCommand(command string, args ...string) (string, error) {
	cmd := exec.Command(command, args...)
	output, err := cmd.CombinedOutput()
	return string(output), err
}

// Middleware de logging
func loggingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		log.Printf("[%s] %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		next(w, r)
		log.Printf("Completed in %v", time.Since(start))
	}
}

// Middleware CORS
func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next(w, r)
	}
}

// Responder com JSON
func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// Dashboard HTML (Interface Web)
func dashboardHandler(w http.ResponseWriter, r *http.Request) {
	html := `<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Proxy Manager Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        @keyframes pulse-green {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .pulse-green {
            animation: pulse-green 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
        }
        .card-hover:hover {
            transform: translateY(-4px);
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
        }
    </style>
</head>
<body class="bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 min-h-screen text-white">
    
    <div class="bg-gray-800 border-b border-gray-700 shadow-lg">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
            <div class="flex justify-between items-center">
                <div class="flex items-center space-x-3">
                    <div class="w-10 h-10 bg-gradient-to-r from-blue-500 to-purple-600 rounded-lg flex items-center justify-center">
                        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
                        </svg>
                    </div>
                    <div>
                        <h1 class="text-2xl font-bold">Proxy Manager</h1>
                        <p class="text-sm text-gray-400">Sistema Multi-Modem 4G</p>
                    </div>
                </div>
                <div class="flex items-center space-x-4">
                    <div class="flex items-center space-x-2">
                        <div id="status-indicator" class="w-3 h-3 bg-green-500 rounded-full pulse-green"></div>
                        <span class="text-sm text-gray-300">Online</span>
                    </div>
                    <button onclick="restartSystem()" class="bg-red-600 hover:bg-red-700 px-4 py-2 rounded-lg font-medium transition-all duration-200 flex items-center space-x-2">
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
                        </svg>
                        <span>Restart Sistema</span>
                    </button>
                </div>
            </div>
        </div>
    </div>

    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
            <div class="bg-gray-800 rounded-xl p-6 border border-gray-700 card-hover transition-all duration-200">
                <div class="flex items-center justify-between">
                    <div>
                        <p class="text-gray-400 text-sm font-medium">Modems Ativos</p>
                        <p id="modem-count" class="text-3xl font-bold mt-2">-</p>
                    </div>
                    <div class="w-12 h-12 bg-blue-500 bg-opacity-20 rounded-lg flex items-center justify-center">
                        <svg class="w-6 h-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
                        </svg>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 rounded-xl p-6 border border-gray-700 card-hover transition-all duration-200">
                <div class="flex items-center justify-between">
                    <div>
                        <p class="text-gray-400 text-sm font-medium">Proxies Online</p>
                        <p id="proxy-count" class="text-3xl font-bold mt-2">-</p>
                    </div>
                    <div class="w-12 h-12 bg-green-500 bg-opacity-20 rounded-lg flex items-center justify-center">
                        <svg class="w-6 h-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"></path>
                        </svg>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 rounded-xl p-6 border border-gray-700 card-hover transition-all duration-200">
                <div class="flex items-center justify-between">
                    <div>
                        <p class="text-gray-400 text-sm font-medium">Uptime</p>
                        <p id="uptime" class="text-xl font-bold mt-2">-</p>
                    </div>
                    <div class="w-12 h-12 bg-purple-500 bg-opacity-20 rounded-lg flex items-center justify-center">
                        <svg class="w-6 h-6 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                    </div>
                </div>
            </div>
        </div>

        <div class="bg-gray-800 rounded-xl p-6 border border-gray-700 mb-8">
            <h2 class="text-xl font-bold mb-6 flex items-center">
                <svg class="w-6 h-6 mr-2 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path>
                </svg>
                Proxies HTTP
            </h2>
            <div id="proxies-container" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <div class="text-center text-gray-400 py-8">Carregando...</div>
            </div>
        </div>

        <div class="bg-gray-800 rounded-xl p-6 border border-gray-700">
            <h2 class="text-xl font-bold mb-6 flex items-center">
                <svg class="w-6 h-6 mr-2 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"></path>
                </svg>
                Modems 4G
            </h2>
            <div id="modems-container" class="space-y-4">
                <div class="text-center text-gray-400 py-8">Carregando...</div>
            </div>
        </div>

    </div>

    <div id="toast" class="fixed bottom-4 right-4 bg-gray-800 border border-gray-700 rounded-lg shadow-2xl p-4 transform translate-y-32 transition-transform duration-300 max-w-sm">
        <div class="flex items-start">
            <div id="toast-icon" class="flex-shrink-0">
                <svg class="w-6 h-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
            </div>
            <div class="ml-3 flex-1">
                <p id="toast-message" class="text-sm font-medium text-white"></p>
            </div>
        </div>
    </div>

    <script>
        let autoRefreshInterval;

        function showToast(message, type) {
            type = type || 'success';
            const toast = document.getElementById('toast');
            const toastMessage = document.getElementById('toast-message');
            const toastIcon = document.getElementById('toast-icon');
            
            toastMessage.textContent = message;
            
            if (type === 'success') {
                toastIcon.innerHTML = '<svg class="w-6 h-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
            } else if (type === 'error') {
                toastIcon.innerHTML = '<svg class="w-6 h-6 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
            } else if (type === 'info') {
                toastIcon.innerHTML = '<svg class="w-6 h-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>';
            }
            
            toast.style.transform = 'translateY(0)';
            setTimeout(function() {
                toast.style.transform = 'translateY(8rem)';
            }, 4000);
        }

        async function fetchStatus() {
            try {
                const response = await fetch('/status');
                const data = await response.json();
                
                if (data.success) {
                    updateDashboard(data.data);
                }
            } catch (error) {
                console.error('Erro ao buscar status:', error);
                document.getElementById('status-indicator').className = 'w-3 h-3 bg-red-500 rounded-full';
            }
        }

        function updateDashboard(data) {
            document.getElementById('modem-count').textContent = data.system.modem_count;
            document.getElementById('proxy-count').textContent = data.proxies.length;
            document.getElementById('uptime').textContent = data.system.uptime || 'N/A';

            const proxiesContainer = document.getElementById('proxies-container');
            if (data.proxies.length === 0) {
                proxiesContainer.innerHTML = '<div class="text-center text-gray-400 py-8 col-span-full">Nenhum proxy ativo</div>';
            } else {
                proxiesContainer.innerHTML = data.proxies.map(function(proxy) {
                    return '<div class="bg-gray-700 rounded-lg p-4 border border-gray-600 hover:border-blue-500 transition-all duration-200">' +
                        '<div class="flex justify-between items-start mb-3">' +
                        '<div>' +
                        '<p class="text-sm text-gray-400">Porta ' + proxy.port + '</p>' +
                        '<p class="text-lg font-bold text-blue-400">' + proxy.public_ip + '</p>' +
                        '</div>' +
                        '<span class="bg-green-500 text-xs px-2 py-1 rounded-full font-medium">Online</span>' +
                        '</div>' +
                        '<button onclick="renewIP(' + proxy.port + ')" class="w-full bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded-lg font-medium transition-all duration-200 flex items-center justify-center space-x-2">' +
                        '<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">' +
                        '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>' +
                        '</svg>' +
                        '<span>Renovar IP</span>' +
                        '</button>' +
                        '</div>';
                }).join('');
            }

            const modemsContainer = document.getElementById('modems-container');
            if (!data.modems || data.modems.length === 0) {
                modemsContainer.innerHTML = '<div class="text-center text-gray-400 py-8">Nenhum modem detectado</div>';
            } else {
                modemsContainer.innerHTML = data.modems.map(function(modem) {
                    var signalColor = getSignalColor(modem.signal);
                    var stateColor = modem.state === 'connected' ? 'bg-green-500' : 'bg-gray-500';
                    var stateIconColor = modem.state === 'connected' ? 'text-green-400' : 'text-gray-400';
                    
                    return '<div class="bg-gray-700 rounded-lg p-4 border border-gray-600">' +
                        '<div class="flex items-center justify-between">' +
                        '<div class="flex-1">' +
                        '<div class="flex items-center space-x-3 mb-2">' +
                        '<p class="font-bold text-lg">Modem ' + modem.id + '</p>' +
                        '<span class="bg-blue-500 text-xs px-2 py-1 rounded-full">' + (modem.interface || 'N/A') + '</span>' +
                        '</div>' +
                        '<div class="grid grid-cols-2 gap-2 text-sm">' +
                        '<div>' +
                        '<p class="text-gray-400">IP Interno</p>' +
                        '<p class="font-mono text-gray-200">' + (modem.internal_ip || 'N/A') + '</p>' +
                        '</div>' +
                        '<div>' +
                        '<p class="text-gray-400">Sinal</p>' +
                        '<p class="font-semibold ' + signalColor + '">' + (modem.signal || 'N/A') + '</p>' +
                        '</div>' +
                        '</div>' +
                        '</div>' +
                        '<div class="ml-4">' +
                        '<div class="w-12 h-12 ' + stateColor + ' bg-opacity-20 rounded-lg flex items-center justify-center">' +
                        '<svg class="w-6 h-6 ' + stateIconColor + '" fill="none" stroke="currentColor" viewBox="0 0 24 24">' +
                        '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.141 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0"></path>' +
                        '</svg>' +
                        '</div>' +
                        '</div>' +
                        '</div>' +
                        '</div>';
                }).join('');
            }
        }

        function getSignalColor(signal) {
            if (!signal) return 'text-gray-400';
            var value = parseInt(signal);
            if (value >= 70) return 'text-green-400';
            if (value >= 50) return 'text-yellow-400';
            return 'text-red-400';
        }

        async function renewIP(port) {
            showToast('Renovando IP da porta ' + port + '...', 'info');
            
            try {
                const response = await fetch('/renew', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({port: port})
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showToast('Renovação iniciada! Aguarde aproximadamente 45 segundos', 'success');
                    setTimeout(fetchStatus, 50000);
                } else {
                    showToast('Erro: ' + data.message, 'error');
                }
            } catch (error) {
                showToast('Erro ao renovar IP', 'error');
            }
        }

        async function restartSystem() {
            if (!confirm('Deseja realmente reiniciar todo o sistema? Todos os proxies ficarão offline por aproximadamente 60 segundos.')) {
                return;
            }
            
            showToast('Reiniciando sistema...', 'info');
            
            try {
                const response = await fetch('/restart', {
                    method: 'POST'
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showToast('Sistema reiniciando. Aguarde aproximadamente 90 segundos', 'success');
                    setTimeout(fetchStatus, 95000);
                } else {
                    showToast('Erro: ' + data.message, 'error');
                }
            } catch (error) {
                showToast('Erro ao reiniciar sistema', 'error');
            }
        }

        function startAutoRefresh() {
            autoRefreshInterval = setInterval(fetchStatus, 30000);
        }

        function stopAutoRefresh() {
            if (autoRefreshInterval) {
                clearInterval(autoRefreshInterval);
            }
        }

        fetchStatus();
        startAutoRefresh();

        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                stopAutoRefresh();
            } else {
                fetchStatus();
                startAutoRefresh();
            }
        });
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}

// Health check
func healthHandler(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "API Proxy Manager está online",
		Data: map[string]string{
			"version": "1.0.0",
			"status":  "healthy",
		},
	})
}

// Restart do sistema
func restartHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Método não permitido. Use POST",
		})
		return
	}

	log.Println("Recebida requisição de restart")

	// Executar restart em goroutine
	go func() {
		output, err := runCommand("sudo", SCRIPT_PATH, "restart")
		if err != nil {
			log.Printf("Erro ao reiniciar: %v\nOutput: %s", err, output)
		} else {
			log.Println("Sistema reiniciado com sucesso")
		}
	}()

	respondJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "Comando de restart enviado. Sistema será reiniciado em alguns segundos.",
	})
}

// Renovar IP de porta específica
func renewPortHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		respondJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Método não permitido. Use POST",
		})
		return
	}

	var req RenewRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, http.StatusBadRequest, Response{
			Success: false,
			Message: "JSON inválido: " + err.Error(),
		})
		return
	}

	if req.Port < 6001 || req.Port > 6010 {
		respondJSON(w, http.StatusBadRequest, Response{
			Success: false,
			Message: "Porta inválida. Use portas entre 6001 e 6010",
		})
		return
	}

	log.Printf("Renovando IP da porta %d", req.Port)

	// RESPONDER IMEDIATAMENTE
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)

	response := Response{
		Success: true,
		Message: "Renovação de IP iniciada. Aguarde ~45 segundos para conclusão.",
		Data:    map[string]int{"port": req.Port},
	}

	json.NewEncoder(w).Encode(response)

	// FORÇAR ENVIO IMEDIATO DA RESPOSTA
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}

	// EXECUTAR EM BACKGROUND (após resposta enviada)
	go func(port int) {
		log.Printf("Iniciando renovação da porta %d em background", port)
		output, err := runCommand("sudo", SCRIPT_PATH, "renew-port", strconv.Itoa(port))

		if err != nil {
			log.Printf("❌ Erro ao renovar porta %d: %v", port, err)
			log.Printf("Output: %s", output)
		} else {
			if strings.Contains(output, "IP RENOVADO COM SUCESSO") {
				log.Printf("✅ Porta %d renovada com sucesso", port)
			} else {
				log.Printf("⚠️  Porta %d: renovação concluída mas pode não ter mudado IP", port)
			}
		}
		log.Printf("Renovação da porta %d finalizada", port)
	}(req.Port)
}

// Status do sistema
func statusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		respondJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Método não permitido. Use GET",
		})
		return
	}

	log.Println("Consultando status")

	modems := getModemStatus()
	proxies := getProxyStatus()
	system := getSystemInfo()

	respondJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "Status obtido com sucesso",
		Data: StatusResponse{
			Modems:  modems,
			Proxies: proxies,
			System:  system,
		},
	})
}

// Obter status dos modems
func getModemStatus() []ModemInfo {
	output, err := runCommand("mmcli", "-L")
	if err != nil {
		log.Printf("Erro ao listar modems: %v", err)
		return []ModemInfo{}
	}

	var modems []ModemInfo
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		if !strings.Contains(line, "Modem/") {
			continue
		}

		modemIdx := strings.Index(line, "Modem/")
		if modemIdx == -1 {
			continue
		}

		afterModem := line[modemIdx+6:]
		var idStr string
		for _, ch := range afterModem {
			if ch >= '0' && ch <= '9' {
				idStr += string(ch)
			} else {
				break
			}
		}

		if idStr == "" {
			continue
		}

		details, err := runCommand("mmcli", "-m", idStr)
		if err != nil {
			log.Printf("Erro ao obter detalhes do modem %s: %v", idStr, err)
			continue
		}

		modem := ModemInfo{
			ID:         idStr,
			State:      "unknown",
			Signal:     "N/A",
			Interface:  "N/A",
			InternalIP: "N/A",
		}

		// Parse do estado e sinal do modem
		for _, detailLine := range strings.Split(details, "\n") {
			trimmed := strings.TrimSpace(detailLine)

			// State: procurar por "state:" seguido do valor
			if strings.Contains(trimmed, "state:") && strings.Contains(trimmed, "|") {
				parts := strings.Split(trimmed, "|")
				if len(parts) >= 2 {
					statePart := strings.TrimSpace(parts[1])
					if strings.HasPrefix(statePart, "state:") {
						stateValue := strings.TrimSpace(strings.TrimPrefix(statePart, "state:"))
						modem.State = stateValue
					}
				}
			}

			// Signal quality: procurar por "signal quality:" e extrair percentual
			if strings.Contains(trimmed, "signal quality:") && strings.Contains(trimmed, "|") {
				parts := strings.Split(trimmed, "|")
				if len(parts) >= 2 {
					signalPart := strings.TrimSpace(parts[1])
					if strings.HasPrefix(signalPart, "signal quality:") {
						signalValue := strings.TrimSpace(strings.TrimPrefix(signalPart, "signal quality:"))
						// Extrair apenas o número e % (ex: "70% (recent)" -> "70%")
						if idx := strings.Index(signalValue, "%"); idx != -1 {
							modem.Signal = strings.TrimSpace(signalValue[:idx+1])
						}
					}
				}
			}
		}

		// Parse do bearer para pegar interface e IP
		if strings.Contains(details, "Bearer") {
			bearerLine := ""
			for _, l := range strings.Split(details, "\n") {
				if strings.Contains(l, "Bearer") && strings.Contains(l, "paths:") {
					bearerLine = l
					break
				}
			}

			if bearerLine != "" {
				// Extrair Bearer ID (último elemento após /)
				parts := strings.Split(bearerLine, "/")
				if len(parts) > 0 {
					bearerID := strings.TrimSpace(parts[len(parts)-1])

					bearerInfo, err := runCommand("mmcli", "-b", bearerID)
					if err == nil {
						for _, bLine := range strings.Split(bearerInfo, "\n") {
							trimmed := strings.TrimSpace(bLine)

							// Interface: procurar "interface:" na linha
							if strings.Contains(trimmed, "interface:") && strings.Contains(trimmed, "|") {
								parts := strings.Split(trimmed, "|")
								if len(parts) >= 2 {
									ifacePart := strings.TrimSpace(parts[1])
									if strings.HasPrefix(ifacePart, "interface:") {
										modem.Interface = strings.TrimSpace(strings.TrimPrefix(ifacePart, "interface:"))
									}
								}
							}

							// Address: procurar "address:" na linha
							if strings.Contains(trimmed, "address:") && strings.Contains(trimmed, "|") {
								parts := strings.Split(trimmed, "|")
								if len(parts) >= 2 {
									addrPart := strings.TrimSpace(parts[1])
									if strings.HasPrefix(addrPart, "address:") {
										modem.InternalIP = strings.TrimSpace(strings.TrimPrefix(addrPart, "address:"))
									}
								}
							}
						}
					} else {
						log.Printf("Erro ao obter bearer %s do modem %s: %v", bearerID, idStr, err)
					}
				}
			}
		}

		log.Printf("Modem adicionado: ID=%s, Interface=%s, IP=%s, State=%s, Signal=%s",
			modem.ID, modem.Interface, modem.InternalIP, modem.State, modem.Signal)

		modems = append(modems, modem)
	}

	log.Printf("Total de modems encontrados: %d", len(modems))

	if modems == nil {
		return []ModemInfo{}
	}

	return modems
}

// Obter status dos proxies
func getProxyStatus() []ProxyInfo {
	var proxies []ProxyInfo

	for port := 6001; port <= 6010; port++ {
		output, err := runCommand("netstat", "-tlnp")
		if err != nil || !strings.Contains(output, fmt.Sprintf(":%d ", port)) {
			continue
		}

		publicIP := getPublicIP(port)

		proxies = append(proxies, ProxyInfo{
			Port:     port,
			PublicIP: publicIP,
			Protocol: "HTTP",
			Modem:    fmt.Sprintf("Modem %d", port-6000),
		})
	}

	return proxies
}

// Obter IP público através de proxy
func getPublicIP(port int) string {
	proxyURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	client := &http.Client{
		Timeout: 5 * time.Second, // Reduzido de 10 para 5 segundos
		Transport: &http.Transport{
			Proxy: http.ProxyURL(mustParseURL(proxyURL)),
		},
	}

	resp, err := client.Get("https://api.ipify.org")
	if err != nil {
		log.Printf("Erro ao obter IP público da porta %d: %v", port, err)
		return "N/A"
	}
	defer resp.Body.Close()

	buf := make([]byte, 256)
	n, err := resp.Body.Read(buf)
	if err != nil && n == 0 {
		return "N/A"
	}

	return strings.TrimSpace(string(buf[:n]))
}

func mustParseURL(rawURL string) *url.URL {
	u, _ := url.Parse(rawURL)
	return u
}

// Obter info do sistema
func getSystemInfo() SystemInfo {
	info := SystemInfo{
		Proxy3Running: false,
		ModemCount:    0,
	}

	// Verificar se 3proxy está rodando
	output, _ := runCommand("pgrep", "3proxy")
	info.Proxy3Running = len(strings.TrimSpace(output)) > 0

	// Contar modems
	output, _ = runCommand("mmcli", "-L")
	info.ModemCount = strings.Count(output, "Modem/")

	// Uptime
	output, _ = runCommand("uptime", "-p")
	info.Uptime = strings.TrimSpace(output)

	return info
}

func main() {
	// Verificar se o script existe
	if _, err := os.Stat(SCRIPT_PATH); os.IsNotExist(err) {
		log.Fatalf("❌ Script não encontrado: %s", SCRIPT_PATH)
	}

	// Rotas
	http.HandleFunc("/", dashboardHandler)
	http.HandleFunc("/health", corsMiddleware(loggingMiddleware(healthHandler)))
	http.HandleFunc("/restart", corsMiddleware(loggingMiddleware(restartHandler)))
	http.HandleFunc("/renew", corsMiddleware(loggingMiddleware(renewPortHandler)))
	http.HandleFunc("/status", corsMiddleware(loggingMiddleware(statusHandler)))

	log.Println("========================================")
	log.Printf("🚀 API Proxy Manager v1.0.0")
	log.Printf("🌐 Dashboard: http://0.0.0.0%s", PORT)
	log.Println("========================================")
	log.Println("📋 Endpoints disponíveis:")
	log.Println("  GET  /         - Dashboard Web")
	log.Println("  GET  /health   - Health check")
	log.Println("  GET  /status   - Status JSON")
	log.Println("  POST /restart  - Reiniciar sistema")
	log.Println("  POST /renew    - Renovar IP de porta")
	log.Println("========================================")

	if err := http.ListenAndServe(PORT, nil); err != nil {
		log.Fatalf("❌ Erro ao iniciar servidor: %v", err)
	}
}
