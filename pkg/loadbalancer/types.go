package loadbalancer

import (
	"sync"
	"time"
)

type Server struct {
	ID            string
	Address       string
	RIF           int32
	Latency       int64
	IsHealthy     bool
	LastProbe     time.Time
	CPUUsage      float64
	CurrentWeight int
}

type ProbeResult struct {
	Timestamp time.Time
	RIF       int32
	Latency   int64
	IsHealthy bool
	CPUUsage  float64
}

type Algorithm string

const (
	AlgorithmPrequal     Algorithm = "prequal"
	AlgorithmRoundRobin  Algorithm = "roundrobin"
	AlgorithmWRR         Algorithm = "wrr"
	AlgorithmRandom      Algorithm = "random"
	AlgorithmLeastLoaded Algorithm = "leastloaded"
)

type Config struct {
	ProbeInterval    time.Duration
	ProbeTimeout     time.Duration
	HealthCheckPath  string
	SelectionChoices int
	Algorithm        Algorithm
	QRIF             float64
}

type Stats struct {
	TotalRequests      uint64
	SuccessfulRequests uint64
	FailedRequests     uint64
	AverageLatency     float64
	mutex              sync.RWMutex
}
