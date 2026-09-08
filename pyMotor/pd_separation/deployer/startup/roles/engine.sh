function set_decode_env() {
    export CANN_INSTALL_PATH="/usr/local/Ascend"
    export MOTOR_LOG_ROOT_PATH="/root/ascend/log"
    export ENGINE_TYPE="vllm"
    export MODEL_NAME="Unknown"
    export NORTH_PLATFORM=None
    export SERVICE_ID="mindie-tmx_20260907212333"
    export VLLM_RPC_TIMEOUT=3600000
    export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
    export HCCL_EXEC_TIMEOUT=3600
    export HCCL_CONNECT_TIMEOUT=3600
    export PYTORCH_NPU_ALLOC_CONF="expandable_segments:True"
    export VLLM_ASCEND_ENABLE_MLAPO=1
    export HCCL_BUFFSIZE=1024
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export OMP_PROC_BIND="false"
    export OMP_NUM_THREADS=10
    export ASCEND_BUFFER_POOL="0:0"
    export VLLM_USE_V1=1
    export VLLM_BLOCK_INACTIVE_MODE="inplace"
}
function set_prefill_env() {
    export CANN_INSTALL_PATH="/usr/local/Ascend"
    export MOTOR_LOG_ROOT_PATH="/root/ascend/log"
    export ENGINE_TYPE="vllm"
    export MODEL_NAME="Unknown"
    export NORTH_PLATFORM=None
    export SERVICE_ID="mindie-tmx_20260907212333"
    export VLLM_RPC_TIMEOUT=3600000
    export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
    export HCCL_EXEC_TIMEOUT=360
    export HCCL_CONNECT_TIMEOUT=600
    export OMP_PROC_BIND=False
    export OMP_NUM_THREADS=10
    export PYTORCH_NPU_ALLOC_CONF="expandable_segments:True"
    export VLLM_ASCEND_ENABLE_MLAPO=1
    export HCCL_BUFFSIZE=256
    export TASK_QUEUE_ENABLE=1
    export HCCL_OP_EXPANSION_MODE="AIV"
    export VLLM_USE_V1=1
    export ASCEND_BUFFER_POOL="0:0"
    export VLLM_BLOCK_INACTIVE_MODE="inplace"
}
#!/bin/bash
# Copyright (c) Huawei Technologies Co., Ltd. 2025-2026. All rights reserved.
# MindIE is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#         http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

if [ "$ROLE" != "prefill" ] && [ "$ROLE" != "decode" ]; then
    echo "Error: This script is for prefill or decode role only. Current ROLE=$ROLE"
    exit 1
fi

setup_jemalloc

gen_ranktable_config
gen_kv_pool_config

set_cann_env

set_mf_store_env

# CRD scenario: refresh JOB_NAME with INFER_SERVICE_INDEX and INSTANCE_INDEX injected by CRD
# Final format: {namespace}-{InferServiceSet_name}-{INFER_SERVICE_INDEX}-p/d{INSTANCE_INDEX}
if [ -n "$INFER_SERVICE_INDEX" ] && [ -n "$INSTANCE_INDEX" ]; then
    if [ "$ROLE" = "prefill" ]; then
        export JOB_NAME="${JOB_NAME}-${INFER_SERVICE_INDEX}-p${INSTANCE_INDEX}"
    elif [ "$ROLE" = "decode" ]; then
        export JOB_NAME="${JOB_NAME}-${INFER_SERVICE_INDEX}-d${INSTANCE_INDEX}"
    fi
    echo "CRD mode: JOB_NAME refreshed to $JOB_NAME"
fi

setup_motor_log_path
setup_ascend_work_path
setup_ascend_cache_path

if [ "$ROLE" = "decode" ]; then
    set_decode_env
elif [ "$ROLE" = "prefill" ]; then
    set_prefill_env
fi

python3 -m motor.node_manager.main &
pid=$!
echo "pull up $ROLE instance"
wait $pid
exit_code=$?
if [ $exit_code -ne 0 ]; then
    echo "Error: mindie daemon exited with code $exit_code"
    exit 1
fi
echo "All processes finished successfully."
exit 0
