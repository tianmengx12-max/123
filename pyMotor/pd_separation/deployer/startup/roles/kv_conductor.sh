function set_kv_conductor_env() {
    export CANN_INSTALL_PATH="/usr/local/Ascend"
    export MOTOR_LOG_ROOT_PATH="/root/ascend/log"
    export ENGINE_TYPE="vllm"
    export MODEL_NAME="Unknown"
    export NORTH_PLATFORM=None
    export SERVICE_ID="mindie-tmx_20260907212333"
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

set_kv_conductor_env

export CONDUCTOR_CONFIG_PATH="$CONFIG_PATH/kv_conductor_config.json"
echo "[kv_conductor] CONDUCTOR_CONFIG_PATH=${CONDUCTOR_CONFIG_PATH}"

if [ -f "$CONFIGMAP_PATH/mooncake_config.py" ]; then
    echo "[kv_conductor] run mooncake_config.py to generate conductor config"
    python3 "$CONFIGMAP_PATH/mooncake_config.py" conductor \
        "$CONDUCTOR_CONFIG_PATH" "$USER_CONFIG_PATH"
    if [ $? -ne 0 ]; then
        echo "[kv_conductor] ERROR: mooncake_config.py execute failed"
        exit 1
    fi
fi

KV_CONDUCTOR_PORT=${KV_CONDUCTOR_PORT:-13333}
KV_CONDUCTOR_HOST=${KV_CONDUCTOR_HOST:-0.0.0.0}
if [[ "$KV_CONDUCTOR_PORT" == *":"* ]]; then
    KV_CONDUCTOR_PORT="${KV_CONDUCTOR_PORT##*:}"
fi

echo "[kv_conductor] Starting KV Conductor on ${KV_CONDUCTOR_HOST}:${KV_CONDUCTOR_PORT}"

# 优先Python模块模式
if python3 -c "import motor.kv_conductor; print('[kv_conductor] python module mode available')" 2>/dev/null; then
    echo "[kv_conductor] launch via python module: motor.kv_conductor"
    exec python3 -m motor.kv_conductor \
        --host "$KV_CONDUCTOR_HOST" \
        --port "$KV_CONDUCTOR_PORT"
fi

# 回退 Rust binary 模式
for bin in \
    "${KV_CONDUCTOR_BIN:-}" \
    /mnt/tmx/MindIE-PyMotor/motor/kv_conductor/bin/kv-conductor \
    /mnt/tmx/MindIE-PyMotor/motor/kv_conductor/target/release/kv-conductor
do
    if [ -n "$bin" ] && [ -x "$bin" ]; then
        echo "[kv_conductor] launch via rust binary: $bin"
        exec "$bin" --host "$KV_CONDUCTOR_HOST" --port "$KV_CONDUCTOR_PORT"
    fi
done

echo "ERROR: motor.kv_conductor missing and no kv-conductor binary found."
exit 1