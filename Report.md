# Replicating: "The Title of Paper You Selected From The List"

**Team Members:**  
Sebastiano Perni (sebastiano.perni@mail.polimi.it);  
Dmitrii Meshcheriakov (email address);  
Paolo Salvi (email address)

---

**Source Paper:**
Bartek Wydrowski, Google Research; Robert Kleinberg, Google Research and Cornell;
Stephen M. Rumble, Google (YouTube); Aaron Archer, Google Research
: Load is not what you should balance: Introducing Prequal. In Proceedings of the 21st USENIX Symposium on Networked Systems Design and Implementation (2024). Published by USENIX NSDI.


**Project:**
- Link to the GitHub repository: https://github.com/sebastiano-perni/loadbalancer

---

# 1. Introduction

Introduce the paper by summarizing:

## The problem the paper addresses and its importance
In big, multi-tenant datacenters loadbalancers typically distribute a huge amount of queries across vast pools of server replicas. The usual load balncing policy used at YouTube, Google and in many other companies is the WRR (Weighted Round Robin), which focuses on balancing CPU utilization across distributed servers in a single job.
However, this paper demonstrates that load is not what you should balance.Infact, focusing on CPU utilization as a primary metric backfires in modern infrastructure due to two critical flaws:
- CPU utilization must be averaged over a time window to be meaningful, so it's not able to detect sudden load shifts. Taking as reference some examples of metrics from the Youtube servers, looking at 1 minute time intervals we a good level of stability of CPU utlization across all the server replicas. While of we look at 1 second time intervals we can see greater underlying variability in the signal, with frequent bursts up to nearly twice the limit.


- Replicas share the hardware with unknown antagonist processes, thus even if the load of a service we want to balance is quite stable, the load on each machine can be greatky variable according also to the load of the antagonists. In case of a spike in the demand of the service, available machines can differ greatly in the capacity of absorbing additional load. Since this availability capacity depends also on the antagonists it cannot be predicted in advance but just detected at runtime. In case of heavy load, WRR can trigger disastrous spikes in tail latency and localized timeouts.


## The key ideas behind its solution and its approach
To overcome the limitations of WRR and similar algorithms, the authors introduce Prequal, which stands for Probing to Reduce Queuing and Latency, a loadbalancing policy designed to reduce the tail latency in multi-tenant datacenters.
Since CPU utilization is not accurate, Prequal use two load signals, RIF (Request in Flight) and latency.
The system exploits the power of d choices paradigm, which consists in  sampling d ≥ 2 servers for their load and sending the next request to the least loaded one.
Prequal categorizes server in hot and cold pool, relative to an estimated RIF distribution quantile. If the entire pool is hot, it picks the server with the absolute lowest RIF to protect hard RAM boundaries. Otherwise, it picks the cold server with the lowest estimated latency.
In order to achieve a succesful result, the design goals of prequal are:
- The minimization of probing overheads.
- Asynchronous probing to add minimal latency.
- Minimization of tail latency thanks to the removal of the worst probes.
- Limitation of RAM footprint of query processing on server replicas.




## The main contributions
- The distinction between hot and cold servers, which guarantees a better load assignment thanks to dynamic classificationGlobalConnect.
- The asynchronous probing system that keeps load metric fresh without adding delay to queries.
- An efficient management of the pools. Prequal alternates between removing the oldest probes and removing the worst probes. This ensures that the average quality of the pool does not degrade over time.

# 2. Selected Result

Mention which result of the paper you are reproducing, and explain its importance.


The main result of the paper we would like to reproduce is the comparison between Prequal and WRR in the case of a multi-server system. In particular we would like to highlight the differences in the tail latency, the rate of requests and their latency for both the algorithms.
To properly evaluate the behavior of the system, we reproduce the load ramp experiment. The aggregate CPU load begins at 75% of the allocation and is incrementally raised in 8 multiplicative steps of 10/9. This progression yields the following specific load levels: 0.75x, 0.83x, 0.93x, 1.03x, 1.14x, 1.27x, 1.41x, 1.57x, and 1.74x of the allocated CPU.

Particular attention is given to the behaviour of the system at peak load and at the tail latency. This is important because one of the primary aim of Prequal is to reduce tail latency and error rates, to allow production systems (such as Youtube) to run at much higher utilization than what could be reached with other types of algorithms. Therefore we expect that, the after the percentage of CPU utilization exceed the 100%, the behaviour of the two algorithms diverge, in particular looking at the latency of the last percentiles, as is possible to observe in Figure 1.


<div style="text-align: center;">
  <img
    alt="Figure 1: This graphs shows the improvement in tail latency achieved in using Prequal compared to WRR"
    src="sources/figure6_original_paper.png"
    style="width:30%;"
    />
  <p>Figure 1: This graphs shows the improvement in tail latency achieved in using Prequal compared to WRR (figure 6 of the original paper)</p>
</div>

# 3. Environment Setup

## Hardware Environment

The experiment has been conducted on the CloudLab platform, using the Utah cluster. More specifically, we used 14 m510
nodes, each with an Intel Xeon D-1548 CPU (8 cores, 16 threads) and 64 GB of RAM. Of the 14 nodes, 1 was used as a load
generator, 1 as a telemetry server (running Prometheus and Grafana), 2 as load balancers, and the remaining ones as
backend servers.

## Software Environment

The experiment is based on a fork of the provided Prequal codebase, which is available at
this [link](https://github.com/omarshaarawi/loadbalancer). The forked repository adds the necessary scripts for running
the experiment and collecting results, as well as code for the further exploration described in section 5.

The software environment is based on Ubuntu 22.04. The included scripts install the following dependencies:

- Go 1.24.1
- Docker (latest version)
- Prometheus (latest Docker image)
- Grafana (latest Docker image)
- Utility tools: wget, curl, git, bc, hey, stress-ng

## Configuration Parameters

The CloudLab profile allows the following parameters to be configured:

- Number of backend servers (default: 10)
- Type of backend servers (default: m510)

The setup scripts allow the following parameters to be configured:

- Number of antagonist servers (default: 3)
- Load of antagonist servers (default: 60% CPU utilization with stress-ng)
- Duration of the load test (default: 180 seconds per phase)

## Deviations from the Original Setup

- **Deviation:** The paper evaluates Prequal on YouTube's production infrastructure, which consists of thousands of
  heterogeneous machines with organic, unpredictable background antagonist workloads. This experiment instead uses a
  10-node CloudLab cluster, simulating antagonists via stress-ng on a fixed subset of nodes.

  **Motivation:** Reproducing the Google environment is infeasible. Our simplified environment provides enough
  statistical evidence to demonstrate Prequal's effectiveness.

- **Deviation:** Prequal's original design implements an asynchronous, bounded probe pool of size 16 with advanced
  eviction rules (age, reuse limit, and highest load) to decouple probing from the critical path and maintain O(1)
  overhead. This experiment instead uses a background timer that synchronously polls all N servers and updates a global
  map.

  **Motivation:** While O(N) probing is problematic in datacenters due to massive scale, in our micro-cluster of 10
  nodes, the overhead is negligible and the implementation is simpler.

- **Deviation:** Prequal's original design calculates the "hot/cold" threshold (Q_RIF) based on an estimated global
  distribution of RIF across all replicas and estimates request latency using the median latency of requests that
  arrived at a similar RIF level. This experiment instead compares only d=2 servers, classifies them as hot/cold, and
  estimates latency via a /health endpoint.

  **Motivation:** While the original design is necessary for large-scale datacenters, our simplified implementation with
  10 nodes is enough to demonstrate Prequal's effectiveness.

# 4. Experiment Result

> Explain how your experiment was conducted and then what results you acquired.
> Afterwards, compare your results with those of the paper and state your
> takeaways.

Step-by-step description:

1. Execution procedure
1. Measurement method (Grafana, Prometheus)
1. Number of runs 
1. Statistical treatment (mean, median, CI, etc.)

Also Describe:

- How did you ensure correctness (did you check also other metrics to make sure the experiment is running correctly?)
- Did you do any debugging? Discuss issues you faced and how you overcame them (if applicable consider allocating a subsection for this item)
 (Grafana + Prometheus, Script for installing stuff on the servers (SUDO, ...),  )
 Changes from the original REPO:
 Script for running
 Load
 Split in two phases
 Bug in the computation of the baseline

Share your result and compare them with the paper's. Then discuss your takeaways.

For comparison include:

- Graph(s) or table(s)
- Matching axes and units with the source paper
- Error bars if applicable
- You may want to report difference with the original results (e.g., absolute
number or percentage).

For example:

<center>
  <div style="display:inline-block; width:30%;">
    <img
      alt="The figure shows that method A improves throughput compared to method B"
      src="figures/one_bar.png"
      style="width:100%"
      />
    <p>Figure 2: The figure shows that method A improves throughput compared to method B</p>
  </div>
  <div style="display:inline-block; width:30%; padding-left: 1em">
    <img
      alt="Our reproduction of Figure 1 shows results with the similar trend as claimed by the paper"
      src="figures/two_bar.png"
      style="width:100%"
      />
    <p>Figure 3: Our reproduction of Figure 1 shows results with the similar trend as claimed by the paper</p>
  </div>
</center>

> **Reminder:** the goal is not achieve the exact results of the paper, but to do a rigorous experiment with similar assumptions from the source paper and gain insight. The insight can be correctness of work, failure to reproduce same results, or even infeasibility of doing such experiment for interesting reasons.

# 5. Further Exploration

In this project you are required to also explore a research question of your own. Either:

1. Take the same test with different input workload or a variation of a test that is not present in the paper and comment the results you obtain
1. Implement a new feature on top of the system you evaluated and show a figure showing the performance

Discuss which approach you take, and what you explored. Explain what was your
motivation and importance of your question.

In the original paper the workload is fixed, while in the original artifact the workload difference between two requests can be at maximum 50% with an average of 25%. Thus, we questioned ourselves about what could happen with a type of workload which is extremely heterogenous in both WRR and Prequal.
In practice we changed the workload assigned to each request in this way:

Base case:
```
work = 2500
```

New version:
```
if work == 0 {
			work = 1000 + int(rand.ExpFloat64()*1500)
			if work > 10000 {
				work = 10000
			}
		}
```

Note that the work correspond to the execution of a SHA 256 algorithm.

What we expect is to see worst performances on tail latency by WRR, since the unlucky servers to which are assigned particularly heavy requests will be extremely penalized. While for average latency we don't expext significative variations.

## 5.1. Methodology and Result

Report the experiment you designed for answering the question and share the
result you got.

Include:

- Graph(s) or table(s)
- How the experiment was conducted (share the details)
- What did you discover?

This experiement remarked again how prequal is effective in managing tail latency, infact we can see a speedup of rouglhy 30x between the 99th percentile of prequal and the 99th percentile of WRR, in case of heavy CPU load.
It's also interesting to observe that, in case of heavy CPU load, prequal tail latency (at the 99.9th percentile) resemble a sort of "slow" inverse exponential, starting from a level A and reaching a asymptotically a level B, where B < A.

# 6. Reproducibility Assessment of the Paper

Evaluate the paper itself:

- Was the methodology clearly described?
- Was the artifact usable? 
- How difficult was reproduction? 

# 7. Conclusion

Conclude the report by mentioning the takeaways of experiments you did


---

# Appendix

You are asked to write this report using Markdown. You can find a cheat sheet
of Markdown syntax at this [link](https://rust-lang.github.io/mdBook/format/markdown.html).

For generating a PDF file from your report you can use a tool of your choice.
*md2pdf* is one such tool. See this [link](https://pypi.org/project/md2pdf/)
for more information about it. You can also use an online editor such as [this](https://www.md2pdf.io/).

