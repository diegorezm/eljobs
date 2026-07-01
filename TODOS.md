## Job queue improvements
- [X] Add job timestamps — record enqueued_at and started_at to measure queue wait time
- [ ] Add max queue depth limit — reject jobs with 429 when queue exceeds a threshold
- [x] Add job retries — retry failed jobs N times before marking as dead
- [x] Dead letter queue — store permanently failed jobs somewhere for inspection

## Metrics to track
- [x] Queue wait time — time from dispatch to worker pickup
- [x] Job execution time — time from worker pickup to completion
- [x] Worker utilization — busy/total ratio over time, expose via /stats
- [ ] Saturation point — at what concurrency does queue depth start growing unbounded
- [x] Throughput — jobs completed per second, computed from jobs_completed + uptime
- [x] Peak queue depth — track the highest queue length ever observed

## Containerization
- [ ] Write a Dockerfile for the Elixir app
- [ ] Add a docker-compose.yml with CPU and memory limits to simulate a real server
- [ ] Add a wrk container to docker-compose so the load test runs inside the network
- [ ] Add make targets — make up, make stress-test, make stats — to run everything easily
- [ ] Test with different CPU limits (0.5, 1.0, 2.0) and compare throughput + saturation point
