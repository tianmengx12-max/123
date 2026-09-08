#!/bin/bash
# 组件 EngineServer | 端口 10000 (service_ports[0], DP0 business) | 策略 auto 自动避让
# 用途：占坑 10000，验证 Engine 业务口被占时自动顺延到空闲口
# 用法：bash hog_engine_10000.sh           # 占坑（默认 vllm-p0，验 d 侧改 DEPLOY=vllm-d0）
#       bash hog_engine_10000.sh cleanup   # 清理
# 预期：Pod 正常 Running，日志含 "busy, using"，矩阵 EngineServer business 登记新端口

NS="mindie-yangan"
DEPLOY="vllm-p0"
CONTAINER="vllm"
PORT="10000"
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
