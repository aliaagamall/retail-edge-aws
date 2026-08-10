# RetailEdge Load Testing

## Overview

This directory contains the load-testing implementation used to evaluate the capacity of the RetailEdge application before finalizing the scaling strategy.

The purpose of the test was to observe how a single application server behaves under increasing concurrent-user workloads and identify when performance starts to degrade.

---

## Technology Stack

The load-testing environment uses:

- **AWS EC2** — application server
- **Amazon Linux** — server operating system
- **Nginx** — reverse proxy
- **Node.js / Express** — application
- **Bash + curl** — load-testing implementation
- **AWS CloudFormation** — infrastructure provisioning

The request flow during the test is:

```text
Load Generator
      |
      v
EC2 :80
      |
      v
Nginx
      |
      v
Node.js / Express :4000
      |
      v
/health
```

Nginx receives requests on port 80 and forwards them to the Node.js application running on port 4000.

---

## Load Test Implementation

The test is implemented in:

```text
scripts/load_test.sh
```

The script accepts the number of concurrent users as an argument:

```bash
./load_test.sh <concurrent_users>
```

Examples:

```bash
./load_test.sh 1000
./load_test.sh 2000
./load_test.sh 8000
./load_test.sh 12000
./load_test.sh 15000
```

Each simulated user sends one request to the `/health` endpoint.

The script measures:

- Total requests
- Successful requests
- Failed requests
- Success rate
- Test duration
- Requests/sec
- Average latency
- Maximum latency

The complete test results are documented in:

```text
load_test_results.md
```

---

## Test Scenario

The project requirements specify:

- **200,000 MAU**
- Previous Black Friday peak: **12,000 concurrent users**
- Previous incident: the system crashed at approximately **8,000 concurrent users**
- Expected upcoming Black Friday peak: **15,000 concurrent users**

The tests were performed at increasing concurrency levels to understand the behavior of the current single-instance deployment.

An important distinction is that **concurrent users are not equivalent to requests/sec**.

The 15,000 value is the expected concurrent-user workload provided by the project requirements. The actual requests/sec depends on how frequently users send requests and which application operations they perform.

---

## Scaling Decision

The load-test results show that the single instance handles the 1,000-user scenario successfully, while performance starts degrading as concurrency increases.

Based on this test, approximately **1,000 concurrent users per instance** is used as a rough planning baseline.

This is not considered an exact production capacity because the test targets the lightweight `/health` endpoint, and real application requests can have significantly different CPU, memory, network, and database requirements.

### Normal Days

For normal traffic, the Auto Scaling configuration will gradually scale the number of application instances according to demand.

The planned maximum capacity for normal operation is:

```text
Max capacity = 10 instances
```

This provides room for horizontal scaling while keeping the normal production configuration bounded.

### Black Friday

Black Friday is treated as a separate, planned traffic event.

The expected workload is:

```text
15,000 concurrent users
```

Using the approximate test baseline:

```text
15,000 / ~1,000 ≈ 15 instances
```

Because the 1,000-user baseline is only an approximation and real application traffic can be heavier than the tested `/health` request, additional headroom is included.

The planned Black Friday capacity is therefore:

```text
17 instances
```

The scaling will still happen **gradually** rather than creating all 17 instances at once.

Scheduled scaling will increase the capacity ahead of the expected Black Friday traffic period, using a different scaling configuration from normal days. Dynamic scaling remains available to respond to unexpected changes in demand.

---

## Directory Structure

```text
load-testing/
├── README.md
├── cloudformation/
│   ├── 01-network.yaml
│   ├── 02-database.yaml
│   └── 03-ec2.yaml
├── demo/
│   └── load-testing-demo.webm
├── load_test_results.md
└── scripts/
    ├── load_test.sh
    └── setup-app-server.sh
```

### Files

- `scripts/load_test.sh` — load-testing script.
- `scripts/setup-app-server.sh` — application server setup.
- `load_test_results.md` — measured results and conclusions.
- `demo/load-testing-demo.webm` — demonstration of the load-testing process.
- `cloudformation/` — CloudFormation templates used to provision the testing infrastructure.