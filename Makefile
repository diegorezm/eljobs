stress-test:
	wrk -t50 -c200 -d30s -s post.lua http://localhost:4000/jobs

stress-test-light:
	wrk -t10 -c50 -d10s -s post.lua http://localhost:4000/jobs
