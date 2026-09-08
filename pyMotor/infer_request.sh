coordinator_ip=$(kubectl get pod -n mindie-tmx -owide --no-headers | awk '$1 ~ /coordinator/ && $2=="1/1"{print $6}')
echo "Coordinator IP: $coordinator_ip"
for i in {1..2}; do
  curl -sS "http://$coordinator_ip:1025/v1/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"Qwen3","prompt":"请详细介绍一下人工智能的发展历史，从图灵测试开始，到符号主义、连接主义、深度学习的兴起，再到现代大语言模型的应用，包括每个阶段的关键人物、重要论文、技术突破以及局限性。同时请分析不同技术路线之间的区别与联系，并展望未来可能的发展方向。","max_tokens":500}' \
    | python -m json.tool --no-ensure-ascii | tee request_out/infer_response.txt
  echo
done





 