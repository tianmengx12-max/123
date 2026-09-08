#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${1:-mindie-tmx}"

cd "${SCRIPT_DIR}/pd_separation/deployer" || {
  echo "Error: deployer directory not found: ${SCRIPT_DIR}/pd_separation/deployer" >&2
  exit 1
}

bash delete.sh "$NAMESPACE"
