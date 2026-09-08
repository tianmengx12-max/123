#!/bin/bash
# Start docker-only single-container PD separation (800I A3, host network).
# Ref: https://gitcode.com/Ascend/MindIE-PyMotor/blob/master/docs/zh/user_guide/deployment/docker/single_container.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGMAP_PATH="${CONFIGMAP_PATH:-${SCRIPT_DIR}/configmap}"
CONTAINER_NAME="${CONTAINER_NAME:-pymotor-single-pd}"
IMAGE_NAME="${IMAGE_NAME:-mindie-motor-vllm:dev-26.0.0.B130-800I-A3-py311-Ubuntu24.04-lts-aarch64-mooncake}"

# 1P1D with p_pod_npu_num=2 and d_pod_npu_num=2 needs 4 NPUs by default.
ASCEND_VISIBLE_DEVICES="${ASCEND_VISIBLE_DEVICES:-0,1,2,3}"

# KV pool: leave KVP_MASTER_SERVICE empty to disable mooncake_master.
KVP_MASTER_SERVICE="${KVP_MASTER_SERVICE:-}"
KV_POOL_PORT="${KV_POOL_PORT:-}"
KV_POOL_EVICTION_HIGH_WATERMARK_RATIO="${KV_POOL_EVICTION_HIGH_WATERMARK_RATIO:-}"
KV_POOL_EVICTION_RATIO="${KV_POOL_EVICTION_RATIO:-}"
DEFAULT_KV_LEASE_TTL="${DEFAULT_KV_LEASE_TTL:-}"

if [ ! -d "${CONFIGMAP_PATH}" ] || [ ! -f "${CONFIGMAP_PATH}/boot.sh" ]; then
    echo "Error: CONFIGMAP_PATH not prepared. Run: bash ${SCRIPT_DIR}/prepare.sh"
    exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    echo "[start] remove existing container: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

ASCEND_DEVICES="--device=/dev/davinci_manager --device=/dev/devmm_svm --device=/dev/hisi_hdc"
IFS=',' read -ra ADDR <<< "${ASCEND_VISIBLE_DEVICES}"
for i in "${ADDR[@]}"; do
    ASCEND_DEVICES="${ASCEND_DEVICES} --device=/dev/davinci${i}"
done

echo "[start] CONFIGMAP_PATH=${CONFIGMAP_PATH}"
echo "[start] IMAGE_NAME=${IMAGE_NAME}"
echo "[start] ASCEND_VISIBLE_DEVICES=${ASCEND_VISIBLE_DEVICES}"
echo "[start] KVP_MASTER_SERVICE=${KVP_MASTER_SERVICE:-<disabled>}"

NODE_IP=$(grep "$(hostname)" /etc/hosts | awk '{print $1}' | head -n1)
if [ -z "${NODE_IP}" ]; then
    NODE_IP=$(hostname -I | awk '{print $1}')
fi

docker run -u root -d --name "${CONTAINER_NAME}" \
    --network host \
    --privileged=true \
    --shm-size=500g \
    -e CONFIGMAP_PATH="${CONFIGMAP_PATH}" \
    -e CONFIG_PATH=/usr/local/Ascend/pyMotor/conf \
    -e ROLE=SINGLE_CONTAINER \
    -e ASCEND_RT_VISIBLE_DEVICES="${ASCEND_VISIBLE_DEVICES}" \
    -e KVP_MASTER_SERVICE="${KVP_MASTER_SERVICE}" \
    -e KV_POOL_PORT="${KV_POOL_PORT}" \
    -e KV_POOL_EVICTION_HIGH_WATERMARK_RATIO="${KV_POOL_EVICTION_HIGH_WATERMARK_RATIO}" \
    -e KV_POOL_EVICTION_RATIO="${KV_POOL_EVICTION_RATIO}" \
    -e DEFAULT_KV_LEASE_TTL="${DEFAULT_KV_LEASE_TTL}" \
    ${ASCEND_DEVICES} \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
    -v /usr/local/dcmi:/usr/local/dcmi \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
    -v /usr/local/sbin:/usr/local/sbin \
    -v /var/log/npu:/usr/slog \
    -v /mnt:/mnt \
    -v /tmp:/tmp \
    -v /home:/home \
    -v /data:/data \
    -v "${CONFIGMAP_PATH}:${CONFIGMAP_PATH}" \
    -v /usr/share/zoneinfo/Asia/Shanghai:/etc/localtime \
    "${IMAGE_NAME}" \
    bash -c 'export POD_IP=$(grep $(hostname) /etc/hosts | awk "{print \$1}" | head -n1) && source $CONFIGMAP_PATH/boot.sh'

echo "[start] container ${CONTAINER_NAME} is running."
echo "  logs: docker logs -f ${CONTAINER_NAME}"
echo "  infer endpoint: http://${NODE_IP}:1025/v1/models"
