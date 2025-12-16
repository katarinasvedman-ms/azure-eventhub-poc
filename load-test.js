import http from 'k6/http';
import { check, sleep } from 'k6';

// Test configuration
// Ramping up to simulate 20,000 requests/second
export const options = {
  stages: [
    { duration: '1m', target: 100 },     // Ramp up to 100 RPS
    { duration: '2m', target: 500 },     // Increase to 500 RPS
    { duration: '3m', target: 2000 },    // Increase to 2000 RPS
    { duration: '5m', target: 5000 },    // Peak at 5000 RPS
    { duration: '2m', target: 0 },       // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% under 500ms, 99% under 1000ms
    http_req_failed: ['rate<0.05'],                  // Failure rate under 5%
  },
  ext: {
    loadimpact: {
      name: 'LogsysNG Event Hub PoC',
      projectID: 3356643,
    }
  }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:5000';

export default function () {
  // Generate a unique partition key for consistent routing
  const partitionKey = `user-${Math.floor(Math.random() * 1000)}`;
  
  const payload = {
    message: `Log event at ${new Date().toISOString()}`,
    source: 'K6LoadTest',
    level: 'INFO',
    partitionKey: partitionKey,
  };

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  // Send single event
  const response = http.post(`${BASE_URL}/api/logs/ingest`, JSON.stringify(payload), params);

  check(response, {
    'status is 202': (r) => r.status === 202,
    'response time < 200ms': (r) => r.timings.duration < 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  // Small sleep to avoid overwhelming the system
  sleep(0.001);
}

// Custom function to test batch endpoint
export function testBatchIngest() {
  const events = Array.from({ length: 100 }, (_, i) => ({
    message: `Batch log event ${i}`,
    source: 'K6BatchTest',
    level: 'INFO',
    partitionKey: `batch-${Math.floor(Math.random() * 100)}`,
  }));

  const payload = { events };

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const response = http.post(`${BASE_URL}/api/logs/ingest-batch`, JSON.stringify(payload), params);

  check(response, {
    'batch status is 202': (r) => r.status === 202,
    'batch response time < 200ms': (r) => r.timings.duration < 200,
  });
}
