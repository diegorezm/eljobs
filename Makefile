# few requests, watch them actually complete
stress-test:
	wrk -t1 -c5 -d10s -s post.lua http://localhost:4000/jobs

# single request, measure one full job lifecycle
test-single:
	curl -X POST http://localhost:4000/jobs \
		-H "Content-Type: application/json" \
		-d '{"payload": "password123"}'

# poll stats every second while a test runs
watch-stats:
	watch -n 1 http http://localhost:4000/stats
