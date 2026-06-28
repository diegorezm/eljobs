# eljobs
 
A job queue built from scratch in Elixir using OTP primitives — no external libraries, just GenServer, Supervisor, and the Erlang `:queue` module.
 
The goal is to explore what you can build with Elixir/OTP when it comes to job queues: how workers are managed, how backpressure works, and how the system behaves under load.
 
## How it works
 
- A `Dispatcher` GenServer receives jobs and routes them to idle workers. If no workers are available, the job is queued.
- A pool of `Worker` GenServers pulls jobs from the dispatcher, executes them, and reports back when done.
- Workers self-register with the dispatcher on startup — the dispatcher never needs to know about workers in advance.
## Running it
 
```bash
iex -S mix
```
 
Dispatch a job:
 
```elixir
iex> Dispatcher.dispatch(%{sleep_for: 2000})
```
 
Check queue stats:
 
```bash
curl http://localhost:4000/stats
```
 
## Load testing
 
```bash
make stress-test
```
 
Uses `wrk` with a lua script to hammer the `/jobs` HTTP endpoint. Adjust concurrency and duration in the `Makefile`.
 
## HTTP API
 
| Method | Path | Description |
|--------|------|-------------|
| POST | `/jobs` | Enqueue a job |
| GET | `/stats` | Queue and worker stats |
 
### POST /jobs
 
```json
{ "sleep_for": 3000 }
```
