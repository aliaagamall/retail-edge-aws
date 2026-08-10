# Load Test Results

## Results

The application was tested against the `/health` endpoint using increasing concurrent-user workloads.

| Concurrent Users | Total Requests | Successful | Failed | Success Rate | Requests/sec | Avg Latency | Max Latency |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 1,000 | 1,000 | 0 | 100% | 99.97 | 2.39s | 8.95s |
| 2,000 | 2,000 | 1,868 | 132 | 93.40% | 159.13 | 3.67s | 10.00s |
| 8,000 | 8,000 | 1,737 | 6,263 | 21.71% | 269.65 | 8.78s | 10.02s |
| 12,000 | 12,000 | 1,908 | 10,092 | 15.90% | 271.07 | 9.07s | 10.01s |
| 15,000 | 15,000 | 2,686 | 12,314 | 17.91% | 263.04 | 8.87s | 10.09s |

## Findings

- **1,000 concurrent users:** 100% of requests succeeded and provided the baseline for capacity planning.
- **2,000 concurrent users:** failures started to appear and average latency increased significantly.
- **8,000 concurrent users:** the single instance experienced severe degradation, with only 21.71% successful requests.
- **12,000 concurrent users:** the success rate dropped to 15.90%.
- **15,000 concurrent users:** only 17.91% of requests succeeded, confirming that a single instance is not sufficient for the expected Black Friday workload.

As concurrency increased beyond the server's practical capacity, throughput stopped increasing proportionally while latency and failures increased.

## Decision

The results support horizontal scaling instead of relying on a single application instance.

For planning purposes, approximately **1,000 concurrent users per instance** is used as a rough baseline from this test.

For the expected **15,000 concurrent-user Black Friday workload**:

```text
15,000 / ~1,000 ≈ 15 instances
```

Because this is an approximate baseline based on a lightweight `/health` endpoint, **17 instances** are planned for the Black Friday scheduled-scaling configuration to provide additional headroom.

Normal-day scaling will use a separate configuration with a maximum of **10 instances**.

The Black Friday configuration will scale capacity **gradually ahead of the expected peak**, rather than treating 17 instances as an immediate fixed deployment.

## Limitation

The test was performed against `/health`, so the measured 1,000 concurrent users per instance should not be treated as an exact production capacity.

Actual capacity depends on the type and complexity of application requests, database usage, resource consumption, and user behavior.

The results are therefore used as a practical infrastructure planning baseline rather than a production-capacity guarantee.