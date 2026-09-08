from ais_bench.benchmark.models import VLLMCustomAPIChatStream

models = [
    dict(
        attr="service",
        type=VLLMCustomAPIChatStream,
        abbr='vllm-api-stream-chat',
        path="/mnt/weight/Qwen3-30B-A3B-W8A8",
        model="Qwen3",
        api_key="",
        request_rate=3.3,
        retry=2,
        host_ip="80.48.37.110",
        host_port=31053,
        max_out_len=131072,
        batch_size=20,
        generation_kwargs=dict(
            temperature=0,
            ignore_eos=True,
            chat_template_kwargs=dict(enable_thinking=False),
        )
    )
]
