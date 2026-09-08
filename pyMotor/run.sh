#user_config_path="/mnt/tmx/Scripts-LLM/motor/pyMotor/user_config"
#user_config_choice=("multi_node" "1_node" "1_node_kv_pool" "1_node_kv_pool_conductor" "1_node_kv_pool_conductor_standby")
#user_config="${user_config_path}/user_config_${user_config_choice[$user_config_index]}.json"
#env="/mnt/tmx/Scripts-LLM/motor/pyMotor/env.json"

kubectl create namespace "mindie-tmx"
cd /mnt/tmx/pyMotor/pd_separation/deployer
#cp /mnt/tmx/Scripts-LLM/motor/pyMotor/boot.sh /mnt/tmx/Scripts-LLM/motor/pyMotor/pd_separation/deployer/startup/
#cp /mnt/tmx/Scripts-LLM/motor/pyMotor/engine_template_multi.yaml /mnt/tmx/Scripts-LLM/motor/pyMotor/pd_separation/deployer/yaml_template/engine_template.yaml
bash delete.sh mindie-tmx
python deploy.py --user_config_path /mnt/tmx/decode-affinity-config/user_config.json --env_config_path /mnt/tmx/decode-affinity-config/env.json
sleep 20s
bash /mnt/tmx/11/pyMotor/show_log.sh

#kubectl get pods -n mindie-tmx 2>/dev/null | grep -qi coordinator || \
  #kubectl apply -f /mnt/tmx/pyMotor/pd_separation/deployer/output_yamls/mindie_motor_coordinator.yaml
