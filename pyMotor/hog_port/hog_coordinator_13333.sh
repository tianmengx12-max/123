#!/bin/bash
# 组件 Coordinator | 端口 13333 (http_server_port) | 策略 auto 自动避让
# 用途：占坑 13333，验证 Conductor callback HTTP 口被占时自动顺延（仅配置 Conductor 时生效）
# 用法：bash hog_coordinator_13333.sh           # 占坑
#       bash hog_coordinator_13333.sh cleanup   # 清理
# 预期：Pod 正常 Running，日志含 "busy, using 13334"，矩阵登记新端口

NS="mindie-yangan"
DEPLOY="mindie-motor-coordinator"
CONTAINER="mindie-motor-coordinator"
PORT="13333"
SIDECAR="port-hog-$PORT"

if [ "${1:-}" = "cleanup" ]; then
  kubectl patch deploy "$DEPLOY" -n "$NS" --type=strategic -p "
spec:
  template:
    spec:
      containers:
      - name: $SIDECAR
        \$patch: delete
"
  echo "已移除占坑 sidecar $SIDECAR"
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
echo "已占坑 $PORT，查看："
echo "  kubectl get pods -n $NS -l app=$DEPLOY"
echo "  kubectl logs -n $NS -l app=$DEPLOY -c $CONTAINER | grep -E 'busy, using|\[Port Matrix\]'"
