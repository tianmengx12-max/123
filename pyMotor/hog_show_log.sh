#!/usr/bin/env bash

# Get the current time, formatted as YYYY-MM-DD_HH-MM-SS
time=$(date +"%Y-%m-%d_%H-%M-%S")
log_dir="/mnt/yangan/log/pyMotor_show_log/pymotor_log_${time}"

# Creating a Log Directory
mkdir -p "$log_dir"

# Retention: keep only the newest 20 log directories, delete older ones
base_dir="/mnt/yangan/log/pyMotor_show_log"
ls -1dt "$base_dir"/*/ 2>/dev/null | tail -n +21 | while read -r old_dir; do
    rm -rf "$old_dir"
    echo "Removed old log dir: $old_dir"
done

# Get all Pods of mindie-pymotor: namespace name node
pods=$(kubectl get pods -A -o wide | grep "mindie-yangan" | awk '{print $1 " " $2 " " $8}')

# Check if a matching Pod is found
if [[ -z "$pods" ]]; then
    echo "No Pods for mindie-pymotor found."
    exit 1
fi

# Capture the interrupt signal and stop all child processes.
trap 'echo "Stop logging..."; pkill -P $$ || true; exit 0' INT TERM

# Process each pod in a loop, logging asynchronously.
# Unlike show_log.sh, this iterates over every container in the pod so that
# multi-container pods (e.g. coordinator + port-hog sidecar) are captured
# instead of failing with "a container name must be specified".
echo "$pods" | while read -r namespace podname nodename; do
    containers=$(kubectl get pod -n "$namespace" "$podname" -o jsonpath='{.spec.containers[*].name}')
    for container in $containers; do
        logfile="${log_dir}/${podname}_${nodename}_${container}.log"
        echo "Logging for Pod [$podname] Container [$container] (Namespace: $namespace) is being recorded to $logfile"
        kubectl logs -f -n "$namespace" "$podname" -c "$container" > "$logfile" 2>&1 &
    done
done

echo "Log recording completed. Logs are saved at $log_dir"
