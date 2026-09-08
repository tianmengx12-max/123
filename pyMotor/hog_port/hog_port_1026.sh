#!/bin/bash
# Scenario 1: hog 1026 on vllm-p0 to verify NodeManager auto-avoid
# Usage: bash hog_port_1026.sh
# Cleanup: bash hog_port_1026.sh cleanup

NS="mindie-yangan"
DEPLOY="vllm-p0"
PORT="1026"
SIDECAR="port-hog-1026"

if [ "${1:-}" = "cleanup" ]; then
  kubectl patch deploy "$DEPLOY" -n "$NS" --type=json \
    -p '[{"op":"remove","path":"/spec/template/spec/containers/1"}]'
  echo "sidecar removed, pod will roll back to 1/1"
  exit 0
fi

IMG=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}')
kubectl patch deploy "$DEPLOY" -n "$NS" --type=strategic -p "
spec:
  template:
    spec:
      containers:
      - name: $SIDECAR
        image: $IMG
        command: [\"python3\",\"-c\",\"import socket,time;s=socket.socket();s.bind(('0.0.0.0',$PORT));s.listen(1);print('HOLD $PORT',flush=True);time.sleep(10**9)\"]
"
echo "patched. check:"
echo "  kubectl get pods -n $NS -l app=$DEPLOY"
echo "  kubectl logs -n $NS -l app=$DEPLOY -c $SIDECAR --tail=3"