# Go Load Balancer

This project is an implementation of the load balancing algorithm described in the paper "Load is not what you should balance: Introducing Prequal" (NSDI '24). It demonstrates key concepts including Power of d choices, RIF (Requests in Flight) tracking, and HCL (Hot-Cold Lexicographic) scoring.

## What's inside

- Power of d choices with HCL (Hot-Cold Lexicographic) scoring
- RIF tracking to see what servers are actually busy
- Health checks that run in the background
- Prometheus metrics and Grafana dashboards for visibility

## Prerequisites

- Go 1.23+
- Docker
- Docker Compose

## Getting started

```bash
git clone https://github.com/omarshaarawi/loadbalancer.git
cd loadbalancer
./setup.sh
```

Or manually:
```bash
docker-compose up --build
```

Then check out:
- Load Balancer at http://localhost:8080
- Prometheus at http://localhost:9090
- Grafana at http://localhost:3001 (login: admin/admin)

## How it works

**Server selection (HCL - Hot-Cold Lexicographic):** Pick d servers at random, calculate RIF threshold at QRIF quantile (default 0.84). Classify servers as "hot" (high RIF) or "cold" (low RIF). If any cold servers exist, pick the one with lowest latency. If all are hot, pick the one with lowest RIF.

**Health checks:** Background goroutine pings all servers on a timer. Dead servers get removed from rotation.

**Metrics:** We export Prometheus metrics for request duration, active connections, server health, and RIF counts.

## Testing it out

Quick test:
```bash
curl http://localhost:8080
```

Check which servers are getting requests:
```bash
for i in {1..20}; do curl -I http://localhost:8080 2>&1 | grep -i "x-served-by"; done
```

Load test with hey:
```bash
go install github.com/rakyll/hey@latest
hey -n 1000 -c 50 http://localhost:8080/
```

Or just loop curl if you want:
```bash
for i in {1..1000}; do curl -s http://localhost:8080 > /dev/null; done
```

Check RIF metrics while load is running:
```bash
curl http://localhost:8080/metrics | grep -E "active_requests|server_rif"
```

## Comparing Algorithms

The repo runs both Prequal and Round-Robin simultaneously so you can compare them in real-time:

- **Prequal**: http://localhost:8080
- **Round-Robin**: http://localhost:8081
- Both share the same backend servers

### Multi-tenant simulation

The backend servers simulate the multi-tenant scenario from the paper:

- **server1**: 60% CPU consumed by antagonist load (contended)
- **server2**: 60% CPU consumed by antagonist load (contended)
- **server3**: No antagonist load (clean server)

This replicates the paper's setup where some servers share machines with heavy background processes. Prequal should detect the slower response times on server1/server2 and route more traffic to server3, while Round-Robin distributes evenly.

### Side-by-side load ramping test

Run the comparison script to test both algorithms at the same time:

```bash
./compare.sh --duration 120
```

This replicates the Paper's Figure 6 methodology:
- Ramps load from 75% to 174% of capacity in 9 steps
- Tests both algorithms in parallel with identical load
- Each step runs for 120 seconds (configurable)
- Shows comparison of latency and throughput

### Viewing results in Grafana

The dashboard (http://localhost:3001) includes an algorithm filter dropdown:
- Select "All" to overlay both algorithms
- Compare latency percentiles (p50, p90, p99, p99.9) side-by-side
- Watch how RIF distribution differs between algorithms
- See which handles load spikes better

## References

Based on the paper: [Load is not what you should balance: Introducing Prequal](https://www.usenix.org/conference/nsdi24/presentation/wydrowski) (NSDI '24)

## Setup Procedure

IMPORTANT: All scripts must be executed from the "client" node.
Connect via SSH to the "client" node (copying the command from CloudLab).
Navigate to the repository directory:

```
cd /local/repository
```

Execute the "initial_setup" script:

```
sudo ./initial_setup.sh
```

Execute the "start_cluster" script:

```
sudo ./start_cluster.sh <algorithm>
```

Where `<algorithm>` can be either roundrobin, wrr, random or leastloaded.
Now all nodes should be online.

### Running the Workload

Execute the run_test script with the same arguments you would use for the compare script:

```
./run_test.sh --duration 180
```

Accessing Grafana
Connect via SSH with localhost port forwarding to the "telemetry" node:

```
ssh -L 3000:localhost:3000 <user>@<server>
```

Note: The `<user>@<server>` string matches the one found on CloudLab for the "telemetry" node (removing the "ssh"
prefix).
You should now be able to access Grafana from your browser by navigating to: http://localhost:3000

NOTE: Grafana only displays data when there is active traffic. If you access Grafana before running the workload, the
dashboard will appear empty.

### Teardown / Closing

When you want to stop everything that was launched by start_cluster, simply run:

```
sudo ./stop_cluster.sh
```

This closes and resets the session (IT ALSO REMOVES ANY ACCUMULATED DATA).

### Synchronizing Changes

If you make a change that needs to be shared across all nodes, you can apply the change on the "client" node and then
run the sync script:

```
sudo ./sync.sh
```

The modification can be done locally, or it could have been pushed to GitHub. In the latter case, simply perform a git
pull on the "client" node before running the sync script.

### Troubleshooting

Permission Failures: If execution fails due to permissions, you might have forgotten to use sudo.
Missing Dependencies: If execution fails because of missing dependencies like Go, Hey, Docker, etc., try installing them
manually on the respective nodes.
Grafana fails to close after stop_cluster: The container on the "telemetry" node might not have stopped. In this case,
connect to that node via SSH and check for running containers using:

```
sudo docker ps
```

If containers are still running, you must stop and remove them manually:

```
sudo docker stop repository-grafana-1
sudo docker rm repository-grafana-1
```

Repeat this process for Prometheus if necessary.
Browser connection to Grafana fails:
You might have used the wrong port.
Try waiting for about thirty seconds.
You might have established the SSH tunnel with localhost to the wrong node.


## Implementation of WRR

```
func (lb *LoadBalancer) selectServerWRR() *Server {
	lb.mutex.RLock()
	defer lb.mutex.RUnlock()

	if len(lb.servers) == 0 {
		return nil
	}

	var best *Server
	var bestCW int32
	var total int32

	for _, server := range lb.servers {
		if !server.IsHealthy {
			continue
		}

		weight := int32((1.0 - server.CPUUsage) * 100)
		if weight < 1 {
			weight = 1
		}

		cw := atomic.AddInt32(&server.CurrentWeight, weight)
		total += weight

		if best == nil || cw > bestCW {
			best = server
			bestCW = cw
		}
	}

	if best != nil {
		atomic.AddInt32(&best.CurrentWeight, -total)
	}

	return best
}
```
