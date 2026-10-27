# Model artifact placeholder

Built with Llama.

The approved model is `meta-llama/Llama-Prompt-Guard-2-22M`, revision `11614a155199674a0a95e6602d6ab0417b790ed0`.

Weights are manually gated. This directory intentionally contains no weights. The scanner holds every job until the operator supplies approved artifacts and the artifact manifest. Do not add credentials or model weights to Git.

Prepare a private build context with `prepare_model.py`. Download access and acceptance of Meta's Llama 4 license are required. The container has no network fallback.

Use `python3 prepare_model.py --local-snapshot /private/approved-artifacts --build-context /private/new-context` for approved browser downloads. Supply exactly LICENSE, USE_POLICY.md, config.json, model.safetensors, special_tokens_map.json, tokenizer.json, and tokenizer_config.json. Both local input and the HF_TOKEN download path verify byte counts and pinned upstream Git blob IDs or the LFS SHA256 before creating the context. Cache symlinks are read as content; output artifacts are regular files. The runtime manifest then records SHA256 for those verified bytes.
