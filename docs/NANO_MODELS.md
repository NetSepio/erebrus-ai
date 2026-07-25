# Nano model candidates

The compiled recovery catalog now includes two Apache-2.0 SmolLM2 Instruct
variants below 0.5B parameters:

| Logical model | Variant | Bytes | SHA-256 | Intended tier |
| --- | --- | ---: | --- | --- |
| SmolLM2 135M Instruct | GGUF Q8_0 | 144,811,072 | `c4a3dd037301b6ecea31d6da37f5cd793ead920dd5ddfe6d589294628d6ce66a` | emergency/constrained |
| SmolLM2 360M Instruct | GGUF Q8_0 | 386,404,992 | `48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201` | Nano |

Both URLs are revision-pinned and installed only after size and SHA-256
verification. The 135M model is an availability floor, not a claim of
assistant-quality parity with the existing 0.5B+ tier. Recommendation tests
ensure a 1 GB device has a viable entry, while capable devices should receive a
larger model based on measured working memory and quality gates.

Provenance:

- `unsloth/SmolLM2-135M-Instruct-GGUF`, revision
  `8637628433dc3df4a2d363adc89e4c3917f299dc`;
- `HuggingFaceTB/SmolLM2-360M-Instruct-GGUF`, revision
  `593b5a2e04c8f3e4ee880263f93e0bd2901ad47f`.
