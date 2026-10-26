# Model artifact placeholder

Built with Llama.

The approved model is `meta-llama/Llama-Prompt-Guard-2-22M`, revision `11614a155199674a0a95e6602d6ab0417b790ed0`.

Weights are manually gated. This directory intentionally contains no weights. The scanner holds every job until the operator supplies approved artifacts and the artifact manifest. Do not add credentials or model weights to Git.

Prepare a private build context with `prepare_model.py`. Download access and acceptance of Meta's Llama 4 license are required. The container has no network fallback.
