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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Prefer the site-packages we overlay. Do this early and again after any
# PYTHONPATH mutation (Ascend toolkit paths must not shadow overlaid vllm).
prefer_overlaid_site_packages() {
    local sp="/usr/local/python3.11.10/lib/python3.11/site-packages"
    local cleaned=""
    local IFS=':'
    for p in ${PYTHONPATH:-}; do
        case "$p" in
            "$sp") continue ;;  # avoid duplicates; we prepend once below
            /tmp/motor|/tmp/motor/*|*/tmp/motor|*/tmp/motor/*) continue ;;
            "") continue ;;
            *) cleaned="${cleaned:+$cleaned:}$p" ;;
        esac
    done
    export PYTHONPATH="${sp}${cleaned:+:$cleaned}"
    echo "[boot] PYTHONPATH=$PYTHONPATH"
}

# Optional: if image drops code under /tmp/motor, move it aside so it cannot win imports.
neutralize_tmp_motor() {
    if [ -e /tmp/motor ]; then
        rm -rf /tmp/motor.bak 2>/dev/null || true
        mv /tmp/motor /tmp/motor.bak
        echo "[boot] backup /tmp/motor -> /tmp/motor.bak"
    fi
}

# ---- 1) motor wheel (all roles) ----
# Candidate roots (ASCII hyphens only). Avoid Unicode "‑" (U+2011) in paths.
TMX_MOTOR_ROOTS=(
    "/mnt/tmx/kv-request/MindIE-PyMotor"
    "/mnt/tmx/guiyihua/MindIE-PyMotor"
    "/mnt/tmx/MindIE-PyMotor"
    "/mnt/MindIE-PyMotor"
)

resolve_under_tmx() {
    # resolve_under_tmx <relpath>  -> prints first existing absolute path
    local rel="$1"
    local root
    for root in "${TMX_MOTOR_ROOTS[@]}"; do
        if [ -e "${root}/${rel}" ]; then
            printf '%s\n' "${root}/${rel}"
            return 0
        fi
    done
    return 1
}

install_motor_wheel() {
    local whl="${MOTOR_WHL:-}"
    local root
    if [ -z "$whl" ] || [ ! -f "$whl" ]; then
        for root in "${TMX_MOTOR_ROOTS[@]}"; do
            whl="$(ls -1t "${root}/dist"/motor-*.whl 2>/dev/null | head -n1 || true)"
            if [ -n "$whl" ] && [ -f "$whl" ]; then
                break
            fi
        done
    fi
    if [ -n "$whl" ] && [ -f "$whl" ]; then
        pip install --force-reinstall --no-deps "$whl"
        echo "[boot] installed motor from $whl"
        chmod +x /usr/local/python3.11.10/lib/python3.11/site-packages/motor/kv_conductor/bin/kv-conductor 2>/dev/null || true
        return 0
    fi
    echo "[boot] WARN: no motor-*.whl under ${TMX_MOTOR_ROOTS[*]} (using image motor)"
    echo "[boot] HINT: ls /mnt/tmx && mount | grep tmx; Pod needs hostPath /mnt/tmx"
    return 1
}

install_motor_wheel || true
neutralize_tmp_motor
prefer_overlaid_site_packages

# ---- 2) BlockInactive on B132 (engine roles) ----
# Default: patch the IMAGE's own vllm in-place. Do NOT copy a newer upstream
# tree into site-packages (causes ScheduledEncoderInputStats / resolve_block_hashes).
# Optional overlay cp only when VLLM_BLOCK_INACTIVE_MODE=overlay and files pass checks.
VLLM_BLOCK_INACTIVE_MODE="${VLLM_BLOCK_INACTIVE_MODE:-inplace}"

# Resolve script paths at runtime (env override still wins).
if [ -z "${PATCH_PY:-}" ]; then
    PATCH_PY="$(resolve_under_tmx scripts/patch_vllm_block_inactive_b132.py || true)"
fi
if [ -z "${FORCE_COORD_PY:-}" ]; then
    FORCE_COORD_PY="$(resolve_under_tmx scripts/force_get_kv_cache_coordinator_b132.py || true)"
fi

verify_block_inactive() {
    TORCH_DEVICE_BACKEND_AUTOLOAD=0 SKIP_RUNTIME_VERIFY="${SKIP_RUNTIME_VERIFY:-}" python3 -c '
import inspect, pathlib, py_compile, sys
print("[boot] sys.path[0:5]=", sys.path[:5])
import vllm
root = pathlib.Path(vllm.__file__).resolve().parent
sched = (root / "v1/core/sched/scheduler.py").read_text(encoding="utf-8")
out = (root / "v1/core/sched/output.py").read_text(encoding="utf-8")
bp = (root / "v1/core/block_pool.py").read_text(encoding="utf-8")
mgr = root / "v1/core/kv_cache_manager.py"
if "ScheduledEncoderInputStats" in sched and "class ScheduledEncoderInputStats" not in out:
    raise SystemExit("BAD: newer-tree scheduler.py (ScheduledEncoderInputStats)")
if "resolve_block_hashes" in bp:
    raise SystemExit("BAD: newer-tree block_pool.py (resolve_block_hashes)")
py_compile.compile(str(mgr), doraise=True)
mgr_txt = mgr.read_text(encoding="utf-8")
if "enable_block_inactive_events: bool = True" not in mgr_txt:
    raise SystemExit("BAD: kv_cache_manager missing enable_block_inactive_events: bool = True")
from vllm.v1.core.kv_cache_coordinator import get_kv_cache_coordinator as g
from vllm.v1.core.kv_cache_manager import KVCacheManager  # noqa: F401
sig = inspect.signature(g)
print("[boot] verify sig=", sig)
assert "enable_block_inactive_events" in sig.parameters, list(sig.parameters)
sig.bind_partial(enable_block_inactive_events=False)
print("[boot] block-inactive verify OK; vllm=", vllm.__file__)
'
}

overlay_is_b132_safe() {
    local src="$1"
    local sched="$src/v1/core/sched/scheduler.py"
    local bp="$src/v1/core/block_pool.py"
    if [ ! -f "$sched" ] || [ ! -f "$bp" ]; then
        echo "[boot] overlay incomplete under $src"
        return 1
    fi
    if grep -q "ScheduledEncoderInputStats" "$sched"; then
        echo "[boot] REJECT overlay: scheduler has ScheduledEncoderInputStats (newer tree)"
        return 1
    fi
    if grep -q "resolve_block_hashes" "$bp"; then
        echo "[boot] REJECT overlay: block_pool has resolve_block_hashes (newer tree)"
        return 1
    fi
    if ! grep -q "enable_block_inactive_events" "$src/v1/core/kv_cache_manager.py" 2>/dev/null; then
        echo "[boot] REJECT overlay: manager missing enable_block_inactive_events"
        return 1
    fi
    return 0
}

patch_vllm_inplace() {
    if [ -z "${PATCH_PY:-}" ] || [ ! -f "$PATCH_PY" ]; then
        echo "[boot] ERROR: missing patch script (PATCH_PY='${PATCH_PY:-}')"
        echo "[boot] looked under: ${TMX_MOTOR_ROOTS[*]}"
        ls -la /mnt/tmx 2>/dev/null || echo "[boot] /mnt/tmx not visible in this container"
        ls -la /mnt/tmx/MindIE-PyMotor/scripts 2>/dev/null || true
        exit 1
    fi
    if [ -z "${FORCE_COORD_PY:-}" ] || [ ! -f "$FORCE_COORD_PY" ]; then
        echo "[boot] ERROR: missing force script (FORCE_COORD_PY='${FORCE_COORD_PY:-}')"
        exit 1
    fi
    echo "[boot] in-place BlockInactive patch via $PATCH_PY"
    # Pod has NPU libs; still allow static-only if set.
    if ! TORCH_DEVICE_BACKEND_AUTOLOAD=0 SKIP_RUNTIME_VERIFY="${SKIP_RUNTIME_VERIFY:-0}" \
        python3 "$PATCH_PY"; then
        echo "[boot] ERROR: patch_vllm_block_inactive failed"
        exit 1
    fi
    echo "[boot] force-patching get_kv_cache_coordinator via $FORCE_COORD_PY"
    if ! TORCH_DEVICE_BACKEND_AUTOLOAD=0 SKIP_RUNTIME_VERIFY="${SKIP_RUNTIME_VERIFY:-0}" \
        python3 "$FORCE_COORD_PY"; then
        echo "[boot] ERROR: force_get_kv_cache_coordinator failed"
        exit 1
    fi
}

apply_overlay_files() {
    local src="$1"
    local root="$2"
    if [ -z "$root" ] || [ ! -d "$root/v1/core" ]; then
        echo "[boot] ERROR: invalid vllm root='$root' (refusing overlay cp)"
        exit 1
    fi
    echo "[boot] applying B132-safe overlay from $src -> $root"
    cp -f "$src/distributed/kv_events.py"        "$root/distributed/"
    cp -f "$src/config/kv_transfer.py"           "$root/config/"
    cp -f "$src/v1/core/block_pool.py"           "$root/v1/core/"
    cp -f "$src/v1/core/kv_cache_coordinator.py" "$root/v1/core/"
    cp -f "$src/v1/core/kv_cache_manager.py"     "$root/v1/core/"
    cp -f "$src/v1/core/sched/scheduler.py"      "$root/v1/core/sched/"
}

resolve_vllm_root() {
    # Plugin/log noise on stdout can poison $(...); keep only the last line.
    local root
    root="$(
        TORCH_DEVICE_BACKEND_AUTOLOAD=0 python3 -c '
import logging
logging.disable(logging.CRITICAL)
import vllm, pathlib
print(pathlib.Path(vllm.__file__).resolve().parent)
' 2>/dev/null | tail -n1
    )"
    if [ -z "$root" ] || [ ! -d "$root/v1/core" ]; then
        echo "[boot] ERROR: invalid vllm root='$root'" >&2
        exit 1
    fi
    echo "[boot] vllm root=$root" >&2
    printf '%s\n' "$root"
}

overlay_vllm_block_inactive() {
    prefer_overlaid_site_packages

    local root src mode
    root="$(resolve_vllm_root)"
    src="${VLLM_OVERLAY:-/mnt/tmx/vllm-block-inactive-overlay}"
    mode="$VLLM_BLOCK_INACTIVE_MODE"

    if [ "$mode" = "overlay" ]; then
        if overlay_is_b132_safe "$src"; then
            apply_overlay_files "$src" "$root"
            find "$root/v1/core" "$root/distributed" "$root/config" \
                -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
            prefer_overlaid_site_packages
            # Heal factory even if overlay coordinator was incomplete.
            TORCH_DEVICE_BACKEND_AUTOLOAD=0 SKIP_RUNTIME_VERIFY="${SKIP_RUNTIME_VERIFY:-0}" \
                python3 "$FORCE_COORD_PY"
        else
            echo "[boot] WARN: overlay unsafe or missing; falling back to in-place patch"
            mode="inplace"
        fi
    fi

    if [ "$mode" = "inplace" ]; then
        patch_vllm_inplace
        find "$root/v1/core" "$root/distributed" "$root/config" \
            -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    elif [ "$mode" != "overlay" ]; then
        echo "[boot] ERROR: unknown VLLM_BLOCK_INACTIVE_MODE=$mode (use inplace|overlay)"
        exit 1
    fi

    prefer_overlaid_site_packages
    if ! verify_block_inactive; then
        echo "[boot] ERROR: block-inactive verify failed"
        exit 1
    fi
    echo "[boot] BlockInactive ready (mode=$mode)"
}

case "$ROLE" in
    "SINGLE_CONTAINER")
        set_cann_env
        overlay_vllm_block_inactive
        source "$SCRIPT_DIR/all_combine_in_single_container.sh"
        ;;
    "prefill"|"decode")
        set_cann_env
        overlay_vllm_block_inactive
        # Re-assert path in case engine.sh/common mutate PYTHONPATH
        prefer_overlaid_site_packages
        source "$SCRIPT_DIR/engine.sh"
        ;;
    "controller")
        source "$SCRIPT_DIR/controller.sh"
        ;;
    "coordinator")
        source "$SCRIPT_DIR/coordinator.sh"
        ;;
    "kv_pool")
        source "$SCRIPT_DIR/kv_pool.sh"
        ;;
    "kv_conductor")
        source "$SCRIPT_DIR/kv_conductor.sh"
        ;;
    "mf_store")
        source "$SCRIPT_DIR/mf_store.sh"
        ;;
    *)
        echo "Error: Unknown ROLE=$ROLE"
        exit 1
        ;;
esac