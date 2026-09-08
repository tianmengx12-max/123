#!/bin/bash
coordinator_ip=$(kubectl get pod -n mindie-tmx -o wide --no-headers \
  | awk '/mindie-motor-coordinator/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){print $i; exit}}')
echo "coordinator ip: ${coordinator_ip}"
while true; do
    curl "http://${coordinator_ip}:1027/metrics" | tee metrics/pymotor_metrics.txt; echo
    # curl "http://${coordinator_ip}:1027/metrics?type=role" | tee metrics/role_metrics.txt; echo
    # curl "http://${coordinator_ip}:1027/metrics?type=dp" | tee metrics/dp_metrics.txt; echo
    # curl "http://${coordinator_ip}:1027/metrics?type=instance" | tee metrics/pd_instance_metrics.txt; echo
    # curl "http://${coordinator_ip}:1027/metrics?type=node" | tee metrics/node_metrics.txt; echo
    sleep 2
done
