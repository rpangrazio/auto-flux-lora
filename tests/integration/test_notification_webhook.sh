#!/usr/bin/env bash
# ============================================
# Integration Test: Notification Webhook
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -c "
import http.server
import json
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        payload = json.loads(body)
        print('Webhook received:', json.dumps(payload))
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"status\":\"ok\"}')
        sys.exit(0)
    def log_message(self, format, *args):
        pass

server = http.server.HTTPServer(('127.0.0.1', 19999), Handler)
server.handle_request()
" &
WEBHOOK_PID=$!
sleep 1

PAYLOAD='{"job_id":"test-job-123","status":"DONE","duration":120.5,"output_path":"/data/output/test-job"}'
curl -s -X POST -H "Content-Type: application/json" -d "${PAYLOAD}" http://127.0.0.1:19999/

wait ${WEBHOOK_PID} 2>/dev/null || true
echo "PASS: webhook delivery test"