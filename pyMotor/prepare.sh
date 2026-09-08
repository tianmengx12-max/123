#!/bin/bash
# Prepare CONFIGMAP_PATH for docker-only single-container PD deployment.
# Ref: https://gitcode.com/Ascend/MindIE-PyMotor/blob/master/docs/zh/user_guide/deployment/docker/single_container.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_PATH="${EXAMPLES_PATH:-${SCRIPT_DIR}/pd_separation}"
CONFIGMAP_PATH="${CONFIGMAP_PATH:-${SCRIPT_DIR}/configmap}"
USER_CONFIG_PATH="${USER_CONFIG_PATH:-${SCRIPT_DIR}/user_config/user_config_docker_only.json}"
ENV_PATH="${ENV_PATH:-${SCRIPT_DIR}/env_docker_only.json}"

DEPLOYER_STARTUP="${EXAMPLES_PATH}/deployer/startup"

if [ ! -d "${DEPLOYER_STARTUP}" ]; then
    echo "Error: deployer startup path not found: ${DEPLOYER_STARTUP}"
    exit 1
fi
if [ ! -f "${USER_CONFIG_PATH}" ]; then
    echo "Error: user config not found: ${USER_CONFIG_PATH}"
    exit 1
fi
if [ ! -f "${ENV_PATH}" ]; then
    echo "Error: env config not found: ${ENV_PATH}"
    exit 1
fi

mkdir -p "${CONFIGMAP_PATH}"

echo "[prepare] copy startup scripts to ${CONFIGMAP_PATH}"
cp -f "${DEPLOYER_STARTUP}/boot.sh" "${CONFIGMAP_PATH}/boot.sh"
cp -f "${DEPLOYER_STARTUP}/common.sh" "${CONFIGMAP_PATH}/common.sh"
cp -f "${DEPLOYER_STARTUP}/hccl_tools.py" "${CONFIGMAP_PATH}/hccl_tools.py"
cp -f "${DEPLOYER_STARTUP}/mooncake_config.py" "${CONFIGMAP_PATH}/mooncake_config.py"
cp -f "${DEPLOYER_STARTUP}/roles/"* "${CONFIGMAP_PATH}/"

# Remove local dev-only lines that may break container startup.
sed -i '/pip install --force-reinstall/d' "${CONFIGMAP_PATH}/boot.sh"

echo "[prepare] copy user_config.json and env.json"
cp -f "${USER_CONFIG_PATH}" "${CONFIGMAP_PATH}/user_config.json"
cp -f "${ENV_PATH}" "${CONFIGMAP_PATH}/env.json"

echo "[prepare] clear stale env functions"
sed -i '/^function set_controller_env()/,/^}/d' "${CONFIGMAP_PATH}/controller.sh"
sed -i '/^function set_coordinator_env()/,/^}/d' "${CONFIGMAP_PATH}/coordinator.sh"
sed -i '/^function set_prefill_env()/,/^}/d' "${CONFIGMAP_PATH}/engine.sh"
sed -i '/^function set_decode_env()/,/^}/d' "${CONFIGMAP_PATH}/engine.sh"
sed -i '/^function set_common_env()/,/^}/d' "${CONFIGMAP_PATH}/common.sh"
sed -i '/^function set_kv_pool_env()/,/^}/d' "${CONFIGMAP_PATH}/kv_pool.sh"
sed -i '/^function set_kv_conductor_env()/,/^}/d' "${CONFIGMAP_PATH}/kv_conductor.sh"
sed -i '/^function set_controller_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/^function set_coordinator_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/^function set_prefill_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/^function set_decode_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/^function set_kv_pool_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/^function set_kv_conductor_env()/,/^}/d' "${CONFIGMAP_PATH}/all_combine_in_single_container.sh"
sed -i '/./,$!d' "${CONFIGMAP_PATH}/common.sh"

echo "[prepare] inject env from set_env_docker.py"
python3 "${DEPLOYER_STARTUP}/set_env_docker.py" --configmap_path "${CONFIGMAP_PATH}"

echo "[prepare] done."
echo "  CONFIGMAP_PATH=${CONFIGMAP_PATH}"
echo "Next: bash ${SCRIPT_DIR}/start_docker_single_pd.sh"
