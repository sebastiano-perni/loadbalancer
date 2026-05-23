package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"
)

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

		work := 1000 + rand.Intn(500)
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
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		if _, err := fmt.Fprintf(w, `{"status":"healthy","server_id":"%s"}`, serverID); err != nil {
			log.Printf("Error writing response: %v", err)
		}
	})

	log.Printf("Server %s starting on port %s", serverID, port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
