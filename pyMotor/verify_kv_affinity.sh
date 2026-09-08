#!/bin/bash
# KV Cache 亲和性调度简单验证脚本
# 用法: bash verify_kv_affinity.sh
# 可选环境变量: NAMESPACE=mindie-tmx MODEL=qwen MAX_TOKENS=128

set -euo pipefail

NAMESPACE="${NAMESPACE:-mindie-tmx}"
MODEL="${MODEL:-qwen}"
PORT="${PORT:-1025}"
CONDUCTOR_PORT="${CONDUCTOR_PORT:-13333}"
MAX_TOKENS="${MAX_TOKENS:-128}"
OUT_DIR="${OUT_DIR:-request_out/kv_affinity_verify}"

mkdir -p "$OUT_DIR"

get_pod_ip() {
  local pattern="$1"
  kubectl get pod -n "$NAMESPACE" -o wide --no-headers \
    | awk -v pat="$pattern" '$1 ~ pat && $2 == "1/1" {
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit }
      }'
}

echo "========== 1. 检查 Pod 状态 =========="
kubectl get pods -n "$NAMESPACE" | tee "$OUT_DIR/pods.txt"
for name in coordinator kv-conductor kv-pool vllm-p0 vllm-d0; do
  if ! grep -q "$name" "$OUT_DIR/pods.txt"; then
    echo "[WARN] 未找到包含 '$name' 的 Pod，请确认部署是否完整。"
  fi
done

COORD_IP="$(get_pod_ip coordinator)"
CONDUCTOR_IP="$(get_pod_ip kv-conductor)"
if [[ -z "$COORD_IP" ]]; then
  echo "[ERROR] 未找到 Running 状态的 Coordinator Pod。"
  exit 1
fi
echo "Coordinator IP : $COORD_IP"
echo "Conductor IP   : ${CONDUCTOR_IP:-unknown}"

echo
echo "========== 2. 检查 Conductor 注册情况 =========="
if [[ -n "$CONDUCTOR_IP" ]]; then
  if ! curl -sS --connect-timeout 3 --max-time 5 \
    "http://${CONDUCTOR_IP}:${CONDUCTOR_PORT}/services" \
    | tee "$OUT_DIR/conductor_services.json" | python3 -m json.tool --no-ensure-ascii 2>/dev/null; then
    echo "[WARN] Conductor /services 无有效 JSON 响应，P 实例可能尚未注册。"
  fi
  echo
else
  echo "[WARN] 跳过 Conductor /services 检查。"
fi

SHARED_PREFIX='以下是一段用于 KV Cache 亲和性验证的固定前缀：在大规模推理系统中，Prefill 阶段负责处理输入 prompt 并生成 KV Cache，Decode 阶段则基于已有 KV 逐 token 生成输出。PD 分离架构将 Prefill 与 Decode 部署在不同实例上，通过 Mooncake 等组件在实例间传输 KV 数据。KV Cache Pool 提供跨请求的 KV 共享存储，Conductor 则维护各 P 实例上的 prefix 索引，Coordinator 在调度时可查询 Conductor，将新请求路由到 prefix 命中更高的 P 实例，从而减少重复 prefill 计算。该机制对多轮对话、RAG 检索增强、批量共享 system prompt 等场景尤为重要。'

build_payload() {
  python3 - "$MODEL" "$1" "$MAX_TOKENS" <<'PY'
import json, sys
model, prompt, max_tokens = sys.argv[1:4]
print(json.dumps({
    "model": model,
    "prompt": prompt,
    "max_tokens": int(max_tokens),
}, ensure_ascii=False))
PY
}

send_request() {
  local label="$1"
  local prompt="$2"
  local outfile="$3"
  local payload timing http_code

  payload="$(build_payload "$prompt")"
  echo ">>> [$label] 发送请求 ..."
  timing="$(
    curl -sS --connect-timeout 10 --max-time 600 \
      -w $'\nTIME_TOTAL=%{time_total}\nTIME_TTFB=%{time_starttransfer}\nHTTP_CODE=%{http_code}\n' \
      -o "$outfile.body" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "http://${COORD_IP}:${PORT}/v1/completions" 2>"$outfile.err"
  )"

  http_code="$(echo "$timing" | awk -F= '/^HTTP_CODE=/{print $2}')"
  time_total="$(echo "$timing" | awk -F= '/^TIME_TOTAL=/{print $2}')"
  time_ttfb="$(echo "$timing" | awk -F= '/^TIME_TTFB=/{print $2}')"

  if [[ "$http_code" != "200" ]]; then
    echo "[ERROR] $label 请求失败, HTTP=$http_code"
    cat "$outfile.err" 2>/dev/null || true
    head -c 500 "$outfile.body" 2>/dev/null || true
    echo
    exit 1
  fi

  python3 -m json.tool --no-ensure-ascii "$outfile.body" > "$outfile.json" 2>/dev/null || cp "$outfile.body" "$outfile.json"

  {
    echo "label=$label"
    echo "http_code=$http_code"
    echo "time_total=${time_total}s"
    echo "time_ttfb=${time_ttfb}s"
  } | tee "$outfile.timing"

  echo "    HTTP=$http_code  总耗时=${time_total}s  首包=${time_ttfb}s"
}

echo
echo "========== 3. 发送验证请求 =========="
echo "说明:"
echo "  - 请求1: 相同 prefix，首次写入 KV Cache"
echo "  - 请求2: 相同 prefix，期望命中 KV 亲和调度 / prefix cache"
echo "  - 请求3: 不同 prefix，作为对照组"

send_request "warmup-1" \
  "${SHARED_PREFIX}【请求1】请用三句话总结上述内容。" \
  "$OUT_DIR/request1"

sleep 2

send_request "affinity-hit" \
  "${SHARED_PREFIX}【请求2】请列出三个关键词。" \
  "$OUT_DIR/request2"

sleep 2

send_request "control-different-prefix" \
  "量子计算的基本原理是什么？请简要说明叠加态、纠缠和测量 collapse 的概念。【对照请求】" \
  "$OUT_DIR/request3"

echo
echo "========== 4. 耗时对比 =========="
python3 <<PY | tee "$OUT_DIR/summary.txt"
from pathlib import Path

def read_timing(path):
    data = {}
    for line in Path(path).read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            data[k.strip()] = v.strip()
    return data

def parse_seconds(value):
    if not value or value == "NA":
        return None
    return float(str(value).rstrip("s"))

out = Path("$OUT_DIR")
rows = []
for name, label in [("request1", "warmup-1"), ("request2", "affinity-hit"), ("request3", "control")]:
    t = read_timing(out / f"{name}.timing")
    rows.append((label, t.get("time_total", "NA"), t.get("time_ttfb", "NA")))

print(f"{'请求':<24} {'总耗时(s)':<12} {'首包(s)':<12}")
print("-" * 50)
for label, total, ttfb in rows:
    print(f"{label:<24} {total:<12} {ttfb:<12}")

r1 = parse_seconds(rows[0][1])
r2 = parse_seconds(rows[1][1])
r3 = parse_seconds(rows[2][1])
if r1 is not None and r2 is not None:
    diff = r1 - r2
    pct = diff / r1 * 100 if r1 > 0 else 0
    print()
    if diff > 0:
        print(f"请求2 比 请求1 总耗时快 {diff:.2f}s ({pct:.1f}%)。")
    else:
        print("请求2 未明显快于 请求1。")
    if r3 is not None:
        if r2 is not None and abs(r2 - r3) / max(r2, r3, 1e-9) < 0.05:
            print("请求2 与 请求3 耗时接近 —— 更像是首次请求预热效应，不能单独证明 KV prefix 命中。")
        elif r3 > r2 * 1.05:
            print("请求3（不同 prefix）明显慢于 请求2 —— 更符合 KV prefix 命中特征。")
PY

echo
echo "========== 5. Coordinator 日志关键字 =========="
COORD_POD="$(kubectl get pod -n "$NAMESPACE" --no-headers | awk '/coordinator/ && $2=="1/1"{print $1; exit}')"
if [[ -n "$COORD_POD" ]]; then
  kubectl logs "$COORD_POD" -n "$NAMESPACE" --tail=300 2>/dev/null \
    | grep -Ei 'KvCacheAffinity|kv_cache_affinity|query success|conductor|fallback to load_balance' \
    | tail -20 | tee "$OUT_DIR/coordinator_kv_logs.txt" || echo "未匹配到相关日志关键字。"
else
  echo "[WARN] 未找到 Coordinator Pod，跳过日志检查。"
fi

echo
echo "========== 完成 =========="
echo "详细响应保存在: $OUT_DIR/"
echo "若请求2首包/总耗时明显低于请求1，且日志中有 kv_cache_affinity / query success，则 KV 亲和性链路基本正常。"
