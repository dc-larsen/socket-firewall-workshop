#!/bin/bash
# Socket Firewall Service Mode Demo

echo "=== Socket Firewall Service Mode Demo ==="
echo ""

# Check containers
echo "1. Container Status:"
docker compose ps --format "   {{.Name}}: {{.Status}}" 2>/dev/null
echo ""

# Show firewall logs
echo "2. Firewall Service Started:"
docker logs socket-firewall 2>&1 | grep "serviceStarted" | head -2 | sed 's/^/   /'
echo ""

# Test allowed package
echo "3. Testing ALLOWED package (lodash):"
docker exec sfw-node-client sh -c 'rm -rf /app/node_modules /app/package*.json 2>/dev/null; npm init -y >/dev/null 2>&1; npm install lodash@4.17.21 2>&1' | tail -3 | sed 's/^/   /'
echo ""

# Test blocked package
echo "4. Testing BLOCKED package (form-data@2.3.3):"
docker exec sfw-node-client npm install form-data@2.3.3 2>&1 | grep -E "(403|Forbidden|error)" | head -3 | sed 's/^/   /'
echo ""

# Show block in logs
echo "5. Firewall Block Log:"
docker logs socket-firewall 2>&1 | grep -E "(packageBlocked|packageAllowed)" | tail -5 | sed 's/^/   /'
echo ""

echo "=== Demo Commands ==="
echo ""
echo "# Install allowed package:"
echo "docker exec sfw-node-client npm install lodash"
echo ""
echo "# Install blocked package (will fail):"
echo "docker exec sfw-node-client npm install form-data@2.3.3"
echo ""
echo "# View firewall logs:"
echo "docker logs -f socket-firewall"
echo ""
