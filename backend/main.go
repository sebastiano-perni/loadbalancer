package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	cpuMu       sync.Mutex
	lastCPUTime float64
	lastCheck   time.Time
	cpuUsage    float64
)

func getProcessCPU() float64 {
	data, err := os.ReadFile("/proc/self/stat")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) < 15 {
		return 0
	}
	utime, _ := strconv.ParseFloat(fields[13], 64)
	stime, _ := strconv.ParseFloat(fields[14], 64)
	return (utime + stime) / 100.0
}

func updateCPU() {
	cpuMu.Lock()
	defer cpuMu.Unlock()
	now := time.Now()
	currentNum := getProcessCPU()

	if !lastCheck.IsZero() {
		dt := now.Sub(lastCheck).Seconds()
		if dt > 0 {
			cpuUsage = (currentNum - lastCPUTime) / dt
			if cpuUsage > 1.0 {
				cpuUsage = 1.0
			}
			if cpuUsage < 0 {
				cpuUsage = 0
			}
		}
	} else {
		cpuUsage = 0
	}
	lastCheck = now
	lastCPUTime = currentNum
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	serverID := os.Getenv("SERVER_ID")
	if serverID == "" {
		serverID = "unknown"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		var work int
		if workParam := r.URL.Query().Get("work"); workParam != "" {
			if parsedWork, err := strconv.Atoi(workParam); err == nil {
				work = parsedWork
			}
		}

		if work == 0 {
			work = 1000 + int(rand.ExpFloat64()*1500)
			if work > 10000 {
				work = 10000
			}
		}

		for i := range work {
			hash := sha256.Sum256([]byte(fmt.Sprintf("%d-%d", time.Now().UnixNano(), i)))
			_ = hex.EncodeToString(hash[:])
		}

		duration := time.Since(start)

		w.Header().Set("Content-Type", "text/html")
		w.Header().Set("X-Served-By", serverID)
		w.WriteHeader(http.StatusOK)
		if _, err := fmt.Fprintf(w, `<!DOCTYPE html>
<html>
<head><title>Backend Server</title></head>
<body>
<h1>Backend Server: %s</h1>
<p>Request processed in %v</p>
</body>
</html>`, serverID, duration); err != nil {
			log.Printf("Error writing response: %v", err)
		}
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		updateCPU()
		cpuMu.Lock()
		curCPU := cpuUsage
		cpuMu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		resp := map[string]interface{}{
			"status":    "healthy",
			"server_id": serverID,
			"cpu_usage": curCPU,
		}
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			log.Printf("Error writing response: %v", err)
		}
	})

	log.Printf("Server %s starting on port %s", serverID, port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
