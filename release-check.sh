#!/bin/bash
set -euo pipefail

echo "=== 1/3 Run tests ==="
swift test

echo "=== 2/3 Build release bundle ==="
bash build.sh

echo "=== 3/3 Deploy ==="
bash deploy.sh

echo "=== Release flow complete ==="
