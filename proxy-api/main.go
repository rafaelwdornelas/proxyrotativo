package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

// ============================================================================
// ESTRUTURAS DE DADOS
// ============================================================================

type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

type Modem struct {
	ID         string `json:"id"`
	Interface  string `json:"interface"`
	InternalIP string `json:"internal_ip"`
	State      string `json:"state"`
	Signal     string `json:"signal"`
}

type Proxy struct {
	Port      int    `json:"port"`
	PublicIP  string `json:"public_ip"`
	Protocol  string `json:"protocol"`
	Modem     string `json:"modem"`
	Running   bool   `json:"running"`
	Interface string `json:"interface,omitempty"`
}

type SystemStatus struct {
	ProxiesRunning int    `json:"proxies_running"`
	ModemCount     int    `json:"modem_count"`
	Uptime         string `json:"uptime"`
	LastUpdate     string `json:"last_update"`
}

type Status struct {
	Modems  []Modem      `json:"modems"`
	Proxies []Proxy      `json:"proxies"`
	System  SystemStatus `json:"system"`
}

type RenewRequest struct {
	Port int `json:"port"`
}

// ============================================================================
// SMS - ESTRUTURAS
// ============================================================================

type SMS struct {
	ID        string    `json:"id"`
	ModemID   string    `json:"modem_id"`
	Number    string    `json:"number"`
	Text      string    `json:"text"`
	Timestamp string    `json:"timestamp"`
	State     string    `json:"state"`
	Received  time.Time `json:"received"`
}

type SendSMSRequest struct {
	ModemID string `json:"modem_id"`
	Number  string `json:"number"`
	Text    string `json:"text"`
}

type SMSManager struct {
	smsCache     map[string]bool
	cacheMutex   sync.RWMutex
	smsHistory   []SMS
	historyMutex sync.RWMutex
	maxHistory   int
}

// ============================================================================
// CONSTANTES
// ============================================================================

const (
	PROXY_MANAGER_PATH = "/home/squid/proxy-system/proxy-manager.sh"
	BASE_PROXY_PORT    = 6000
	BASE_SOCKS_PORT    = 7000
	MAX_MODEMS         = 100
	SMS_CHECK_INTERVAL = 10 * time.Second
	SMS_MAX_HISTORY    = 100
)

// ============================================================================
// VARIÁVEIS GLOBAIS
// ============================================================================

var (
	statusCache      *Status
	statusCacheMutex sync.RWMutex
	statusCacheTime  time.Time
	cacheTTL         = 30 * time.Second
	smsManager       *SMSManager
)

// ============================================================================
// INICIALIZAÇÃO
// ============================================================================

func init() {
	smsManager = &SMSManager{
		smsCache:   make(map[string]bool),
		smsHistory: make([]SMS, 0),
		maxHistory: SMS_MAX_HISTORY,
	}
}

func main() {
	router := mux.NewRouter()

	// Rotas do sistema
	router.HandleFunc("/health", healthHandler).Methods("GET")
	router.HandleFunc("/status", statusHandler).Methods("GET")
	router.HandleFunc("/restart", restartHandler).Methods("POST")
	router.HandleFunc("/renew", renewHandler).Methods("POST")

	// Rotas SMS
	router.HandleFunc("/sms/inbox", smsInboxHandler).Methods("GET")
	router.HandleFunc("/sms/inbox/{modem_id}", smsInboxByModemHandler).Methods("GET")
	router.HandleFunc("/sms/send", smsSendHandler).Methods("POST")
	router.HandleFunc("/sms/history", smsHistoryHandler).Methods("GET")
	router.HandleFunc("/sms/delete", smsDeleteHandler).Methods("POST")

	router.Use(corsMiddleware)
	router.PathPrefix("/").Handler(http.FileServer(http.Dir(".")))

	// Iniciar polling de SMS em background
	go startSMSPolling()

	log.Println("========================================")
	log.Println("🚀 API Proxy Manager v2.0 + SMS")
	log.Println("========================================")
	log.Println("📡 Servidor: http://0.0.0.0:5000")
	log.Println("📱 SMS Polling: Ativo (10s)")
	log.Println("========================================")
	log.Fatal(http.ListenAndServe("0.0.0.0:5000", router))
}

// ============================================================================
// HANDLERS - SISTEMA
// ============================================================================

func healthHandler(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, APIResponse{
		Success: true,
		Message: "API Proxy Manager está online",
		Data: map[string]string{
			"version":    "2.0.1",
			"status":     "healthy",
			"max_modems": strconv.Itoa(MAX_MODEMS),
			"sms":        "enabled",
		},
	})
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	status := getSystemStatus()

	respondJSON(w, APIResponse{
		Success: true,
		Message: "Status obtido com sucesso",
		Data:    status,
	})
}

func restartHandler(w http.ResponseWriter, r *http.Request) {
	log.Println("🔄 Recebida solicitação de restart do sistema")

	go func() {
		time.Sleep(2 * time.Second)

		cmd := exec.Command("sudo", PROXY_MANAGER_PATH, "restart")
		output, err := cmd.CombinedOutput()

		if err != nil {
			log.Printf("❌ Erro ao reiniciar: %v - %s", err, string(output))
		} else {
			log.Println("✅ Sistema reiniciado com sucesso")
		}

		invalidateCache()
	}()

	respondJSON(w, APIResponse{
		Success: true,
		Message: "Comando de restart enviado. Sistema será reiniciado em alguns segundos.",
	})
}

func renewHandler(w http.ResponseWriter, r *http.Request) {
	var req RenewRequest

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Dados inválidos: " + err.Error(),
		})
		return
	}

	if req.Port < BASE_PROXY_PORT+1 || req.Port > BASE_PROXY_PORT+MAX_MODEMS {
		respondJSON(w, APIResponse{
			Success: false,
			Message: fmt.Sprintf("Porta inválida. Deve estar entre %d e %d", BASE_PROXY_PORT+1, BASE_PROXY_PORT+MAX_MODEMS),
		})
		return
	}

	log.Printf("🔄 Recebida solicitação de renovação de IP para porta %d", req.Port)

	go func() {
		cmd := exec.Command("sudo", PROXY_MANAGER_PATH, "renew-port", strconv.Itoa(req.Port))
		output, err := cmd.CombinedOutput()

		if err != nil {
			log.Printf("❌ Erro ao renovar porta %d: %v - %s", req.Port, err, string(output))
		} else {
			log.Printf("✅ IP da porta %d renovado com sucesso", req.Port)
		}

		invalidateCache()
	}()

	respondJSON(w, APIResponse{
		Success: true,
		Message: "Renovação de IP iniciada. Aguarde ~45 segundos para conclusão.",
		Data: map[string]int{
			"port": req.Port,
		},
	})
}

// ============================================================================
// SMS - POLLING E GERENCIAMENTO
// ============================================================================

func startSMSPolling() {
	log.Println("📱 SMS Polling iniciado...")

	ticker := time.NewTicker(SMS_CHECK_INTERVAL)
	defer ticker.Stop()

	checkAllModemsForSMS()

	for range ticker.C {
		checkAllModemsForSMS()
	}
}

func checkAllModemsForSMS() {
	modems := getActiveModems()

	for _, modem := range modems {
		smsList := getSMSFromModem(modem.ID)

		for _, sms := range smsList {
			cacheKey := fmt.Sprintf("%s-%s", modem.ID, sms.ID)

			smsManager.cacheMutex.RLock()
			alreadyProcessed := smsManager.smsCache[cacheKey]
			smsManager.cacheMutex.RUnlock()

			if !alreadyProcessed {
				log.Printf("📩 Novo SMS | Modem: %s | De: %s | Texto: %s", modem.ID, sms.Number, sms.Text)

				smsManager.cacheMutex.Lock()
				smsManager.smsCache[cacheKey] = true
				smsManager.cacheMutex.Unlock()

				smsManager.historyMutex.Lock()
				smsManager.smsHistory = append(smsManager.smsHistory, sms)
				if len(smsManager.smsHistory) > smsManager.maxHistory {
					smsManager.smsHistory = smsManager.smsHistory[len(smsManager.smsHistory)-smsManager.maxHistory:]
				}
				smsManager.historyMutex.Unlock()

				processCommandSMS(modem.ID, sms)
			}
		}
	}
}

func getActiveModems() []Modem {
	status := getSystemStatus()
	return status.Modems
}

func getSMSFromModem(modemID string) []SMS {
	smsList := make([]SMS, 0)

	cmd := exec.Command("mmcli", "-m", modemID, "--messaging-list-sms")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return smsList
	}

	re := regexp.MustCompile(`SMS/(\d+)`)
	matches := re.FindAllStringSubmatch(string(output), -1)

	for _, match := range matches {
		if len(match) > 1 {
			smsID := match[1]
			sms := getSMSDetails(modemID, smsID)
			if sms != nil {
				smsList = append(smsList, *sms)
			}
		}
	}

	return smsList
}

func getSMSDetails(modemID, smsID string) *SMS {
	cmd := exec.Command("mmcli", "-m", modemID, "--sms", smsID)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil
	}

	smsData := string(output)

	number := extractValue(smsData, `number:\s*(.+)`)
	text := extractValue(smsData, `text:\s*(.+)`)
	timestamp := extractValue(smsData, `timestamp:\s*(.+)`)
	state := extractValue(smsData, `state:\s*(.+)`)

	return &SMS{
		ID:        smsID,
		ModemID:   modemID,
		Number:    strings.TrimSpace(number),
		Text:      strings.TrimSpace(text),
		Timestamp: strings.TrimSpace(timestamp),
		State:     strings.TrimSpace(state),
		Received:  time.Now(),
	}
}

func sendSMS(modemID, number, text string) error {
	if !strings.HasPrefix(number, "+") {
		number = "+" + number
	}

	createCmd := fmt.Sprintf("text='%s',number='%s'", text, number)
	cmd := exec.Command("mmcli", "-m", modemID, "--messaging-create-sms="+createCmd)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("erro ao criar SMS: %v - %s", err, string(output))
	}

	re := regexp.MustCompile(`SMS/(\d+)`)
	match := re.FindStringSubmatch(string(output))
	if len(match) < 2 {
		return fmt.Errorf("não foi possível extrair ID do SMS")
	}

	smsID := match[1]

	sendCmd := exec.Command("mmcli", "-m", modemID, "--sms", smsID, "--send")
	output, err = sendCmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("erro ao enviar SMS: %v - %s", err, string(output))
	}

	time.Sleep(2 * time.Second)

	deleteCmd := exec.Command("mmcli", "-m", modemID, "--sms", smsID, "--delete")
	deleteCmd.Run()

	log.Printf("✅ SMS enviado | Modem: %s | Para: %s | Texto: %s", modemID, number, text)

	return nil
}

func deleteSMS(modemID, smsID string) error {
	// Usar sudo para apagar SMS
	deleteArg := fmt.Sprintf("--messaging-delete-sms=%s", smsID)
	cmd := exec.Command("sudo", "mmcli", "-m", modemID, deleteArg)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("erro ao apagar SMS: %v - %s", err, string(output))
	}

	log.Printf("🗑️  SMS apagado | Modem: %s | SMS: %s", modemID, smsID)
	return nil
}

func processCommandSMS(modemID string, sms SMS) {
	text := strings.TrimSpace(strings.ToUpper(sms.Text))

	if strings.HasPrefix(text, "RENEW") {
		re := regexp.MustCompile(`RENEW\s+(\d+)`)
		match := re.FindStringSubmatch(text)
		if len(match) > 1 {
			port := match[1]
			log.Printf("🔄 Comando SMS: RENEW porta %s", port)

			go func() {
				cmd := exec.Command("sudo", PROXY_MANAGER_PATH, "renew-port", port)
				output, err := cmd.CombinedOutput()

				var resposta string
				if err == nil && strings.Contains(string(output), "RENOVADO COM SUCESSO") {
					resposta = fmt.Sprintf("✅ IP da porta %s renovado!", port)
				} else {
					resposta = fmt.Sprintf("❌ Falha ao renovar porta %s", port)
				}

				sendSMS(modemID, sms.Number, resposta)
			}()
		}
	}

	if text == "STATUS" {
		log.Printf("📊 Comando SMS: STATUS")
		go func() {
			status := getSystemStatus()
			resposta := fmt.Sprintf("Sistema OK - %d modems, %d proxies ativos", status.System.ModemCount, status.System.ProxiesRunning)
			sendSMS(modemID, sms.Number, resposta)
		}()
	}

	if text == "HELP" {
		log.Printf("ℹ️  Comando SMS: HELP")
		go func() {
			resposta := "Comandos: RENEW <porta> | STATUS | HELP"
			sendSMS(modemID, sms.Number, resposta)
		}()
	}
}

// ============================================================================
// SMS - HANDLERS HTTP
// ============================================================================

func smsInboxHandler(w http.ResponseWriter, r *http.Request) {
	modems := getActiveModems()
	allSMS := make(map[string][]SMS)

	for _, modem := range modems {
		smsList := getSMSFromModem(modem.ID)
		if len(smsList) > 0 {
			allSMS[modem.ID] = smsList
		}
	}

	respondJSON(w, APIResponse{
		Success: true,
		Message: "Lista de SMS obtida com sucesso",
		Data:    allSMS,
	})
}

func smsInboxByModemHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	modemID := vars["modem_id"]

	smsList := getSMSFromModem(modemID)

	respondJSON(w, APIResponse{
		Success: true,
		Message: fmt.Sprintf("SMS do modem %s obtidos com sucesso", modemID),
		Data:    smsList,
	})
}

func smsSendHandler(w http.ResponseWriter, r *http.Request) {
	var req SendSMSRequest

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Dados inválidos: " + err.Error(),
		})
		return
	}

	if req.ModemID == "" || req.Number == "" || req.Text == "" {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Campos obrigatórios: modem_id, number, text",
		})
		return
	}

	if err := sendSMS(req.ModemID, req.Number, req.Text); err != nil {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Erro ao enviar SMS: " + err.Error(),
		})
		return
	}

	respondJSON(w, APIResponse{
		Success: true,
		Message: "SMS enviado com sucesso",
		Data: map[string]string{
			"modem_id": req.ModemID,
			"number":   req.Number,
			"text":     req.Text,
		},
	})
}

func smsHistoryHandler(w http.ResponseWriter, r *http.Request) {
	smsManager.historyMutex.RLock()
	history := make([]SMS, len(smsManager.smsHistory))
	copy(history, smsManager.smsHistory)
	smsManager.historyMutex.RUnlock()

	respondJSON(w, APIResponse{
		Success: true,
		Message: "Histórico de SMS obtido com sucesso",
		Data: map[string]interface{}{
			"total": len(history),
			"sms":   history,
		},
	})
}

func smsDeleteHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ModemID string `json:"modem_id"`
		SMSID   string `json:"sms_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Dados inválidos: " + err.Error(),
		})
		return
	}

	if err := deleteSMS(req.ModemID, req.SMSID); err != nil {
		respondJSON(w, APIResponse{
			Success: false,
			Message: "Erro ao apagar SMS: " + err.Error(),
		})
		return
	}

	respondJSON(w, APIResponse{
		Success: true,
		Message: "SMS apagado com sucesso",
	})
}

// ============================================================================
// FUNÇÕES DE STATUS
// ============================================================================

func getSystemStatus() *Status {
	statusCacheMutex.RLock()
	if time.Since(statusCacheTime) < cacheTTL && statusCache != nil {
		defer statusCacheMutex.RUnlock()
		return statusCache
	}
	statusCacheMutex.RUnlock()

	statusCacheMutex.Lock()
	defer statusCacheMutex.Unlock()

	status := &Status{
		Modems:  make([]Modem, 0),
		Proxies: make([]Proxy, 0),
		System:  SystemStatus{},
	}

	modems := getModems()
	status.Modems = modems
	status.System.ModemCount = len(modems)

	proxies := getProxies(modems)
	status.Proxies = proxies
	status.System.ProxiesRunning = countRunningProxies(proxies)

	uptime := getUptime()
	status.System.Uptime = uptime
	status.System.LastUpdate = time.Now().Format("2006-01-02 15:04:05")

	statusCache = status
	statusCacheTime = time.Now()

	return status
}

func getModems() []Modem {
	modems := make([]Modem, 0)

	cmd := exec.Command("mmcli", "-L")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return modems
	}

	re := regexp.MustCompile(`Modem/(\d+)`)
	matches := re.FindAllStringSubmatch(string(output), -1)

	for _, match := range matches {
		if len(match) > 1 {
			modemID := match[1]
			modem := getModemDetails(modemID)
			if modem != nil {
				modems = append(modems, *modem)
			}
		}
	}

	return modems
}

func getModemDetails(modemID string) *Modem {
	cmd := exec.Command("mmcli", "-m", modemID)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil
	}

	modemData := string(output)

	state := extractValue(modemData, `state:\s*(.+)`)
	signal := extractValue(modemData, `signal quality:\s*(\d+)`)

	bearerPath := extractValue(modemData, `Bearer.*(/org/freedesktop/ModemManager1/Bearer/\d+)`)
	var iface, ip string

	if bearerPath != "" {
		bearerID := strings.Split(bearerPath, "/")
		if len(bearerID) > 0 {
			bid := bearerID[len(bearerID)-1]
			cmd := exec.Command("mmcli", "-b", bid)
			bearerOutput, err := cmd.CombinedOutput()
			if err == nil {
				bearerData := string(bearerOutput)
				iface = extractValue(bearerData, `interface:\s*(.+)`)
				ip = extractValue(bearerData, `address:\s*(.+)`)
			}
		}
	}

	if signal != "" {
		signal = signal + "%"
	}

	return &Modem{
		ID:         modemID,
		Interface:  strings.TrimSpace(iface),
		InternalIP: strings.TrimSpace(ip),
		State:      strings.TrimSpace(state),
		Signal:     signal,
	}
}

func getProxies(modems []Modem) []Proxy {
	proxies := make([]Proxy, 0)

	proxyIPCache := make(map[int]string)
	var wg sync.WaitGroup
	var mu sync.Mutex

	for i := 1; i <= len(modems); i++ {
		port := BASE_PROXY_PORT + i
		wg.Add(1)

		go func(p int) {
			defer wg.Done()
			publicIP := getPublicIP(p)
			mu.Lock()
			proxyIPCache[p] = publicIP
			mu.Unlock()
		}(port)
	}

	wg.Wait()

	for i, modem := range modems {
		httpPort := BASE_PROXY_PORT + i + 1
		socksPort := BASE_SOCKS_PORT + i + 1

		publicIP := proxyIPCache[httpPort]

		proxies = append(proxies, Proxy{
			Port:      httpPort,
			PublicIP:  publicIP,
			Protocol:  "HTTP",
			Modem:     fmt.Sprintf("Modem %s", modem.ID),
			Running:   isProxyRunning(httpPort),
			Interface: modem.Interface,
		})

		proxies = append(proxies, Proxy{
			Port:      socksPort,
			PublicIP:  publicIP,
			Protocol:  "SOCKS5",
			Modem:     fmt.Sprintf("Modem %s", modem.ID),
			Running:   isProxyRunning(socksPort),
			Interface: modem.Interface,
		})
	}

	return proxies
}

func isProxyRunning(port int) bool {
	pidFile := fmt.Sprintf("/var/run/3proxy_%d.pid", port)

	data, err := os.ReadFile(pidFile)
	if err != nil {
		return false
	}

	pid := strings.TrimSpace(string(data))
	procPath := fmt.Sprintf("/proc/%s/cmdline", pid)

	_, err = os.Stat(procPath)
	return err == nil
}

func getPublicIP(port int) string {
	proxyURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	cmd := exec.Command("curl", "-s", "-x", proxyURL, "--max-time", "5", "https://api.ipify.org")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "N/A"
	}

	return strings.TrimSpace(string(output))
}

func countRunningProxies(proxies []Proxy) int {
	count := 0
	for _, proxy := range proxies {
		if proxy.Running {
			count++
		}
	}
	return count
}

func getUptime() string {
	cmd := exec.Command("uptime", "-p")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "N/A"
	}
	return strings.TrimSpace(string(output))
}

// ============================================================================
// FUNÇÕES AUXILIARES
// ============================================================================

func extractValue(data, pattern string) string {
	re := regexp.MustCompile(pattern)
	match := re.FindStringSubmatch(data)
	if len(match) > 1 {
		return match[1]
	}
	return ""
}

func invalidateCache() {
	statusCacheMutex.Lock()
	statusCache = nil
	statusCacheMutex.Unlock()
}

func respondJSON(w http.ResponseWriter, response APIResponse) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}
