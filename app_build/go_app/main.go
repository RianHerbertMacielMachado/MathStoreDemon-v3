package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// ─── Embeds: lua54.exe e todos os arquivos .lua ───────────────────────────────
//
//go:embed lua54.exe fivem_deob/*.lua fivem_deob/luraph_lift/*.lua
var embeddedFiles embed.FS

// ─── HTML da interface (embutido no binário) ──────────────────────────────────
//
//go:embed ui.html
var uiHTML []byte

// ─── Estado global ────────────────────────────────────────────────────────────
var (
	mu          sync.Mutex
	logLines    []string
	isRunning   bool
	currentProc *exec.Cmd
	tmpDir      string
	outputDir   string
	lastResult  map[string]interface{}
)

// ─── Extrai arquivos embutidos para temp dir ──────────────────────────────────
func extractEmbedded() (string, error) {
	dir, err := os.MkdirTemp("", "fivem_deob_*")
	if err != nil {
		return "", err
	}

	// Extrai lua54.exe
	luaData, err := embeddedFiles.ReadFile("lua54.exe")
	if err != nil {
		return "", fmt.Errorf("lua54.exe not embedded: %v", err)
	}
	luaPath := filepath.Join(dir, "lua54.exe")
	if err := os.WriteFile(luaPath, luaData, 0755); err != nil {
		return "", err
	}

	// Extrai todos os .lua do fivem_deob/
	err = fs.WalkDir(embeddedFiles, "fivem_deob", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		data, err := embeddedFiles.ReadFile(path)
		if err != nil {
			return err
		}
		dest := filepath.Join(dir, path)
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			return err
		}
		return os.WriteFile(dest, data, 0644)
	})
	if err != nil {
		return "", fmt.Errorf("failed to extract lua modules: %v", err)
	}

	return dir, nil
}

// ─── Handler: página principal ───────────────────────────────────────────────
func handleUI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(uiHTML)
}

// ─── Handler: análise (POST) ─────────────────────────────────────────────────
type AnalyzeRequest struct {
	ResourceDir  string `json:"resourceDir"`
	ResourceName string `json:"resourceName"`
	OutputDir    string `json:"outputDir"`
	MaxTicks     string `json:"maxTicks"`
	Verbose      bool   `json:"verbose"`
}

func handleAnalyze(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != "POST" {
		http.Error(w, `{"error":"method not allowed"}`, 405)
		return
	}

	mu.Lock()
	if isRunning {
		mu.Unlock()
		w.Write([]byte(`{"error":"analysis already running"}`))
		return
	}
	isRunning = true
	logLines = []string{}
	mu.Unlock()

	var req AnalyzeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		mu.Lock(); isRunning = false; mu.Unlock()
		w.Write([]byte(`{"error":"invalid request"}`))
		return
	}

	if req.ResourceDir == "" {
		mu.Lock(); isRunning = false; mu.Unlock()
		w.Write([]byte(`{"error":"resourceDir is required"}`))
		return
	}

	if req.MaxTicks == "" {
		req.MaxTicks = "3"
	}

	outDir := req.OutputDir
	if outDir == "" {
		outDir = filepath.Join(req.ResourceDir, "deob_output")
	}
	mu.Lock(); outputDir = outDir; mu.Unlock()

	// Inicia análise em goroutine
	go runAnalysis(req, outDir)

	w.Write([]byte(`{"ok":true}`))
}

func runAnalysis(req AnalyzeRequest, outDir string) {
	addLog("=== Iniciando FiveM Deob ===")
	addLog(fmt.Sprintf("Resource: %s", req.ResourceDir))
	if req.ResourceName != "" {
		addLog(fmt.Sprintf("Nome: %s", req.ResourceName))
	}
	addLog(fmt.Sprintf("Saída: %s", outDir))
	addLog("")

	// Monta comando
	luaExe := filepath.Join(tmpDir, "lua54.exe")
	deobEntry := filepath.Join(tmpDir, "fivem_deob", "deob.lua")

	args := []string{
		deobEntry,
		req.ResourceDir,
		"--output", outDir,
		"--max-ticks", req.MaxTicks,
	}
	if req.ResourceName != "" {
		args = append(args, "--resource-name", req.ResourceName)
	}
	if req.Verbose {
		args = append(args, "--verbose")
	}

	cmd := exec.Command(luaExe, args...)

	// LUA_PATH para encontrar os módulos (usa separador correto do OS)
	luaParent := tmpDir
	sep := string(filepath.Separator)
	luaPath := luaParent + sep + "?.lua;" +
		luaParent + sep + "?" + sep + "init.lua;;"
	cmd.Env = append(os.Environ(), "LUA_PATH="+luaPath)

	// Captura stdout+stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		addLog("ERRO: " + err.Error())
		mu.Lock(); isRunning = false; mu.Unlock()
		return
	}
	cmd.Stderr = cmd.Stdout // merge

	mu.Lock(); currentProc = cmd; mu.Unlock()

	if err := cmd.Start(); err != nil {
		addLog("ERRO ao iniciar lua54.exe: " + err.Error())
		mu.Lock(); isRunning = false; currentProc = nil; mu.Unlock()
		return
	}

	// Lê saída linha a linha
	buf := make([]byte, 4096)
	var partial string
	for {
		n, err := stdout.Read(buf)
		if n > 0 {
			text := partial + string(buf[:n])
			lines := strings.Split(text, "\n")
			for i, l := range lines {
				// Remove ANSI
				l = stripANSI(l)
				if i < len(lines)-1 {
					if l != "" {
						addLog(l)
					}
				} else {
					partial = l // última linha pode estar incompleta
				}
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			break
		}
	}
	if partial != "" {
		addLog(stripANSI(partial))
	}

	cmd.Wait()
	rc := cmd.ProcessState.ExitCode()

	if rc == 0 {
		addLog("")
		addLog("✓ ANÁLISE CONCLUÍDA COM SUCESSO!")
		addLog(fmt.Sprintf("  Arquivos em: %s", outDir))
	} else {
		addLog(fmt.Sprintf("✗ Finalizado com código %d", rc))
	}

	mu.Lock()
	isRunning = false
	currentProc = nil
	lastResult = map[string]interface{}{
		"ok":        rc == 0,
		"outputDir": outDir,
		"exitCode":  rc,
	}
	mu.Unlock()
}

// ─── Handler: stream de logs (Server-Sent Events) ────────────────────────────
func handleLogs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", 500)
		return
	}

	offset := 0
	for {
		mu.Lock()
		lines := logLines[offset:]
		running := isRunning
		mu.Unlock()

		for _, line := range lines {
			data, _ := json.Marshal(map[string]interface{}{
				"line":    line,
				"running": running,
			})
			fmt.Fprintf(w, "data: %s\n\n", data)
			offset++
		}
		flusher.Flush()

		if !running && len(lines) == 0 && offset > 0 {
			// Sinaliza fim
			data, _ := json.Marshal(map[string]interface{}{
				"done":   true,
				"result": lastResult,
			})
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
			return
		}

		select {
		case <-r.Context().Done():
			return
		case <-time.After(200 * time.Millisecond):
		}
	}
}

// ─── Handler: status ─────────────────────────────────────────────────────────
func handleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	mu.Lock()
	defer mu.Unlock()
	data, _ := json.Marshal(map[string]interface{}{
		"running":   isRunning,
		"outputDir": outputDir,
		"logCount":  len(logLines),
	})
	w.Write(data)
}

// ─── Handler: para análise ───────────────────────────────────────────────────
func handleStop(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	mu.Lock()
	proc := currentProc
	mu.Unlock()
	if proc != nil {
		proc.Process.Kill()
	}
	w.Write([]byte(`{"ok":true}`))
}

// ─── Handler: abrir pasta de saída ───────────────────────────────────────────
func handleOpenOutput(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	mu.Lock()
	outDir := outputDir
	mu.Unlock()
	if outDir == "" {
		w.Write([]byte(`{"error":"no output dir"}`))
		return
	}
	var err error
	switch runtime.GOOS {
	case "windows":
		err = exec.Command("explorer", outDir).Start()
	case "darwin":
		err = exec.Command("open", outDir).Start()
	default:
		err = exec.Command("xdg-open", outDir).Start()
	}
	if err != nil {
		w.Write([]byte(fmt.Sprintf(`{"error":"%s"}`, err.Error())))
		return
	}
	w.Write([]byte(`{"ok":true}`))
}

// ─── Handler: listar conteúdo de um diretório ────────────────────────────────
func handleListDir(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	dir := r.URL.Query().Get("path")
	if dir == "" {
		homeDir, _ := os.UserHomeDir()
		dir = homeDir
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		data, _ := json.Marshal(map[string]interface{}{"error": err.Error()})
		w.Write(data)
		return
	}
	type Entry struct {
		Name  string `json:"name"`
		IsDir bool   `json:"isDir"`
	}
	result := []Entry{}
	// Adiciona ".." para navegar para cima
	parent := filepath.Dir(dir)
	if parent != dir {
		result = append(result, Entry{Name: "..", IsDir: true})
	}
	for _, e := range entries {
		result = append(result, Entry{Name: e.Name(), IsDir: e.IsDir()})
	}
	data, _ := json.Marshal(map[string]interface{}{
		"path":    dir,
		"entries": result,
	})
	w.Write(data)
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
func addLog(line string) {
	mu.Lock()
	logLines = append(logLines, line)
	mu.Unlock()
}

var ansiRe = strings.NewReplacer(
	"\x1b[0m", "", "\x1b[1m", "", "\x1b[2m", "", "\x1b[31m", "",
	"\x1b[32m", "", "\x1b[33m", "", "\x1b[36m", "", "\x1b[0m", "",
)

func stripANSI(s string) string {
	// Remove sequências ANSI \x1b[...m
	result := []rune{}
	inEsc := false
	for _, c := range s {
		if c == '\x1b' {
			inEsc = true
			continue
		}
		if inEsc {
			if c == 'm' {
				inEsc = false
			}
			continue
		}
		result = append(result, c)
	}
	return string(result)
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	cmd.Start()
}

func findFreePort() int {
	l, err := net.Listen("tcp", ":0")
	if err != nil {
		return 7842
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

// ─── Main ─────────────────────────────────────────────────────────────────────
func main() {
	var err error
	tmpDir, err = extractEmbedded()
	if err != nil {
		log.Fatalf("Failed to extract embedded files: %v\n", err)
	}
	defer os.RemoveAll(tmpDir)

	port := findFreePort()
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	url := fmt.Sprintf("http://%s", addr)

	http.HandleFunc("/", handleUI)
	http.HandleFunc("/api/analyze", handleAnalyze)
	http.HandleFunc("/api/logs", handleLogs)
	http.HandleFunc("/api/status", handleStatus)
	http.HandleFunc("/api/stop", handleStop)
	http.HandleFunc("/api/open-output", handleOpenOutput)
	http.HandleFunc("/api/list-dir", handleListDir)

	fmt.Printf("FiveM Deob iniciando em %s\n", url)

	// Abre o navegador após um pequeno delay
	go func() {
		time.Sleep(500 * time.Millisecond)
		openBrowser(url)
		fmt.Printf("Abrindo %s no navegador...\n", url)
	}()

	log.Fatal(http.ListenAndServe(addr, nil))
}
