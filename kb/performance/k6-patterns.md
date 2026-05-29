## k6 Load Test Patterns

Reusable k6 script patterns for the three standard test modes used in this factory.

**When to use**:
- Performance agent: ramp test (standard gate)
- Red Team: spike + soak (adversarial)

**Trade-offs / gotchas**:
- k6 runs against local dev instance — ensure it's running before executing
- Thresholds are hard gates: non-zero exit code = CI failure
- Use `--env BASE_URL=http://localhost:PORT` to avoid hardcoding

**Standard Ramp Test (Performance gate)**:
```javascript
// scripts/hooks/k6-ramp.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  stages: [
    { duration: '1m', target: 50 },   // ramp up
    { duration: '1m', target: 50 },   // hold
    { duration: '1m', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<300', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/your-endpoint`);
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
```

**Spike Test (Red Team)**:
```javascript
export const options = {
  stages: [
    { duration: '10s', target: 10 },
    { duration: '30s', target: 500 },  // sudden spike
    { duration: '1m', target: 10 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1000'],  // relaxed for spike
    http_req_failed: ['rate<0.05'],
  },
};
```

**Soak Test (Red Team)**:
```javascript
export const options = {
  stages: [
    { duration: '30s', target: 30 },
    { duration: '5m', target: 30 },   // sustained load
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};
```

Run: `k6 run --env BASE_URL=http://localhost:3000 scripts/hooks/k6-ramp.js`
