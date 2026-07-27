#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const [inputPath, outputPath = inputPath] = process.argv.slice(2);
if (!inputPath) {
  throw new Error("Usage: node tool/rebuild_model_catalog.mjs INPUT [OUTPUT]");
}

const additions = {
  "smollm2-360m-instruct": [
    mlx("mlx-community/SmolLM2-360M-Instruct-bf16-mlx", "BF16", {
      minimumRamGB: 0.9,
      recommendedRamGB: 1.3,
      upstream: "HuggingFaceTB/SmolLM2-360M-Instruct",
    }),
  ],
  "qwen3.5-0.8b": [
    mlx("mlx-community/Qwen3.5-0.8B-MLX-4bit", "4bit", {
      minimumRamGB: 1.4,
      recommendedRamGB: 2.2,
      upstream: "Qwen/Qwen3.5-0.8B",
    }),
  ],
  "qwen3.5-2b": [
    mlx("mlx-community/Qwen3.5-2B-4bit", "4bit", {
      minimumRamGB: 2.5,
      recommendedRamGB: 4,
      upstream: "Qwen/Qwen3.5-2B",
    }),
  ],
  "qwen3-1.7b": [
    mlx("mlx-community/Qwen3-1.7B-4bit", "4bit", {
      minimumRamGB: 2,
      recommendedRamGB: 3,
      upstream: "Qwen/Qwen3-1.7B",
    }),
    gguf("Qwen/Qwen3-1.7B-GGUF", "Qwen3-1.7B-Q8_0.gguf", "Q8_0", {
      minimumRamGB: 2.5,
      recommendedRamGB: 3.5,
      official: true,
    }),
  ],
  "llama-3.2-1b-instruct": [
    mlx("mlx-community/Llama-3.2-1B-Instruct-4bit", "4bit", {
      minimumRamGB: 1.5,
      recommendedRamGB: 2.5,
      upstream: "meta-llama/Llama-3.2-1B-Instruct",
    }),
  ],
  "llama-3.2-3b-instruct": [
    mlx("mlx-community/Llama-3.2-3B-Instruct-4bit", "4bit", {
      minimumRamGB: 3,
      recommendedRamGB: 5,
      upstream: "meta-llama/Llama-3.2-3B-Instruct",
    }),
  ],
  "gemma-3n-e2b-it": [
    mlx("mlx-community/gemma-3n-E2B-it-4bit", "4bit", {
      minimumRamGB: 4,
      recommendedRamGB: 6,
      upstream: "google/gemma-3n-E2B-it",
    }),
  ],
  "phi-4-mini-instruct": [
    mlx("mlx-community/Phi-4-mini-instruct-4bit", "4bit", {
      minimumRamGB: 3.5,
      recommendedRamGB: 5,
      upstream: "microsoft/Phi-4-mini-instruct",
    }),
  ],
  "gemma-3-4b-it": [
    mlx("mlx-community/gemma-3-4b-it-4bit", "4bit", {
      minimumRamGB: 4,
      recommendedRamGB: 6,
      upstream: "google/gemma-3-4b-it",
    }),
  ],
  "qwen3-8b": [
    mlx("mlx-community/Qwen3-8B-4bit", "4bit", {
      minimumRamGB: 6,
      recommendedRamGB: 10,
      upstream: "Qwen/Qwen3-8B",
    }),
    gguf("Qwen/Qwen3-8B-GGUF", "Qwen3-8B-Q4_K_M.gguf", "Q4_K_M", {
      minimumRamGB: 6,
      recommendedRamGB: 10,
      official: true,
    }),
  ],
  "qwen3-14b": [
    mlx("mlx-community/Qwen3-14B-4bit", "4bit", {
      minimumRamGB: 10,
      recommendedRamGB: 16,
      upstream: "Qwen/Qwen3-14B",
    }),
    gguf("Qwen/Qwen3-14B-GGUF", "Qwen3-14B-Q4_K_M.gguf", "Q4_K_M", {
      minimumRamGB: 10,
      recommendedRamGB: 16,
      official: true,
    }),
  ],
};

function mlx(repositoryId, quantization, options) {
  return {
    kind: "mlx",
    repositoryId,
    quantization,
    ...options,
  };
}

function gguf(repositoryId, filename, quantization, options) {
  return {
    kind: "gguf",
    repositoryId,
    filename,
    quantization,
    ...options,
  };
}

const catalog = JSON.parse(await readFile(inputPath, "utf8"));
const apiCache = new Map();

async function repository(repositoryId) {
  if (!apiCache.has(repositoryId)) {
    apiCache.set(
      repositoryId,
      fetch(
        `https://huggingface.co/api/models/${repositoryId}?blobs=true`,
      ).then(async (response) => {
        if (!response.ok) {
          throw new Error(`${repositoryId}: Hugging Face returned ${response.status}`);
        }
        return response.json();
      }),
    );
  }
  return apiCache.get(repositoryId);
}

async function sha256For(repositoryId, revision, sibling) {
  if (sibling.lfs?.sha256) return sibling.lfs.sha256;
  const response = await fetch(
    `https://huggingface.co/${repositoryId}/resolve/${revision}/${encodePath(sibling.rfilename)}`,
  );
  if (!response.ok) {
    throw new Error(`${repositoryId}/${sibling.rfilename}: download returned ${response.status}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  return createHash("sha256").update(bytes).digest("hex");
}

async function pinnedFile({
  repositoryId,
  filename,
  role,
  format,
  quantization = "",
  backend,
  artifactId,
  required = true,
}) {
  const repo = await repository(repositoryId);
  const sibling = repo.siblings.find((file) => file.rfilename === filename);
  if (!sibling) {
    throw new Error(`${repositoryId}: ${filename} is not available`);
  }
  const revision = repo.sha;
  return {
    artifact_id: artifactId,
    role,
    format,
    ...(quantization ? { quantization } : {}),
    filename,
    repository_id: repositoryId,
    revision,
    download_url:
      `https://huggingface.co/${repositoryId}/resolve/${revision}/${encodePath(filename)}?download=true`,
    file_size_bytes: sibling.size,
    sha256: await sha256For(repositoryId, revision, sibling),
    backend,
    required,
  };
}

function encodePath(value) {
  return value.split("/").map(encodeURIComponent).join("/");
}

function slug(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function provenance(repositoryId, { official = false, upstream } = {}) {
  const publisher = repositoryId.split("/")[0];
  return {
    kind: official ? "official" : "community_conversion",
    publisher,
    repository_id: repositoryId,
    ...(upstream ? { upstream_repository_id: upstream } : {}),
    verification: "immutable_revision_size_and_sha256",
  };
}

async function mlxVariant(model, definition) {
  const repo = await repository(definition.repositoryId);
  const filenames = repo.siblings
    .map((file) => file.rfilename)
    .filter((filename) =>
      /^(config\.json|generation_config\.json|tokenizer\.json|tokenizer_config\.json|special_tokens_map\.json|chat_template\.jinja|model.*\.safetensors(?:\.index\.json)?)$/.test(
        filename,
      ),
    );
  const roleFor = (filename) => {
    if (filename.startsWith("model") && filename.endsWith(".safetensors")) {
      return "model";
    }
    if (filename.includes("tokenizer") || filename === "special_tokens_map.json") {
      return "tokenizer";
    }
    if (filename === "chat_template.jinja") return "chat_template";
    return "config";
  };
  const files = [];
  for (const filename of filenames) {
    const role = roleFor(filename);
    files.push(
      await pinnedFile({
        repositoryId: definition.repositoryId,
        filename,
        role,
        format: filename.endsWith(".safetensors") ? "safetensors" : "json",
        backend: "mlx",
        artifactId: `${slug(definition.repositoryId)}-${slug(filename)}`,
        required: filename !== "generation_config.json",
      }),
    );
  }
  if (!files.some((file) => file.role === "model")) {
    throw new Error(`${definition.repositoryId}: no MLX model weights found`);
  }
  return {
    variant_id: `${model.id}-mlx-${slug(definition.quantization)}`,
    model_id: model.id,
    format: "mlx",
    quantization: definition.quantization,
    platforms: ["ios-arm64", "macos-arm64"],
    compatible_backends: ["mlx"],
    minimum_ram_gb: definition.minimumRamGB,
    recommended_ram_gb: definition.recommendedRamGB,
    release_channel: "stable",
    status: "active",
    provenance: provenance(definition.repositoryId, {
      upstream: definition.upstream,
    }),
    files,
  };
}

async function ggufVariant(model, definition) {
  const file = await pinnedFile({
    repositoryId: definition.repositoryId,
    filename: definition.filename,
    role: "model",
    format: "gguf",
    quantization: definition.quantization,
    backend: "llama.cpp",
    artifactId: `${slug(definition.repositoryId)}-${slug(definition.filename)}`,
  });
  return {
    variant_id: `${model.id}-gguf-${slug(definition.quantization)}-${slug(definition.repositoryId.split("/")[0])}`,
    model_id: model.id,
    format: "gguf",
    quantization: definition.quantization,
    platforms: model.device_support?.platforms ?? [],
    compatible_backends: ["llama.cpp"],
    minimum_ram_gb: definition.minimumRamGB,
    recommended_ram_gb: definition.recommendedRamGB,
    release_channel: "stable",
    status: "active",
    provenance: provenance(definition.repositoryId, {
      official: definition.official,
    }),
    files: [file],
  };
}

async function refreshFile(file) {
  if (!file.repository_id || !file.filename) return file;
  const refreshed = await pinnedFile({
    repositoryId: file.repository_id,
    filename: file.filename,
    role: file.role ?? "model",
    format: file.format ?? "",
    quantization: file.quantization ?? "",
    backend: file.backend ?? "llama.cpp",
    artifactId: file.artifact_id ?? file.id ?? slug(file.filename),
    required: file.required !== false,
  });
  return {
    ...file,
    ...refreshed,
    id: file.id,
    artifact_id: file.artifact_id,
    recommended: file.recommended,
    platforms: file.platforms,
    notes: file.notes,
  };
}

async function refreshVariant(model, variant) {
  const files = [];
  for (const file of variant.files ?? []) files.push(await refreshFile(file));
  const repositoryId = files[0]?.repository_id ?? "";
  return {
    ...variant,
    status: variant.status ?? "active",
    provenance:
      variant.provenance ??
      provenance(repositoryId, {
        official: repositoryId.startsWith("Qwen/"),
      }),
    files,
  };
}

for (const model of catalog.models) {
  const refreshedArtifacts = [];
  for (const artifact of model.artifacts ?? []) {
    refreshedArtifacts.push(await refreshFile(artifact));
  }
  model.artifacts = refreshedArtifacts;

  const variants = [];
  for (const variant of model.variants ?? []) {
    variants.push(await refreshVariant(model, variant));
  }

  if (
    refreshedArtifacts.length > 0 &&
    !variants.some(
      (variant) =>
        variant.files?.[0]?.repository_id === refreshedArtifacts[0].repository_id &&
        variant.files?.[0]?.filename === refreshedArtifacts[0].filename,
    )
  ) {
    variants.push({
      variant_id: `${model.id}-gguf-${slug(
        refreshedArtifacts.find((file) => file.role === "model")
          ?.quantization ?? "default",
      )}`,
      model_id: model.id,
      format: "gguf",
      quantization:
        refreshedArtifacts.find((file) => file.role === "model")
          ?.quantization ?? "",
      platforms: model.device_support?.platforms ?? [],
      compatible_backends: ["llama.cpp"],
      minimum_ram_gb: model.device_support?.minimum_ram_gb ?? 0,
      recommended_ram_gb: model.device_support?.recommended_ram_gb ?? 0,
      release_channel: model.status?.release_channel ?? "stable",
      status: "active",
      provenance: provenance(refreshedArtifacts[0].repository_id, {
        official: refreshedArtifacts[0].repository_id.startsWith("Qwen/"),
      }),
      files: refreshedArtifacts.map(({ id, ...file }) => ({
        ...file,
        artifact_id: file.artifact_id ?? id,
      })),
    });
  }

  for (const definition of additions[model.id] ?? []) {
    const candidate =
      definition.kind === "mlx"
        ? await mlxVariant(model, definition)
        : await ggufVariant(model, definition);
    const existingIndex = variants.findIndex(
      (variant) => variant.variant_id === candidate.variant_id,
    );
    if (existingIndex >= 0) variants[existingIndex] = candidate;
    else variants.push(candidate);
  }

  model.variants = variants;
  model.preferred_variant_id =
    variants.find((variant) => variant.format === "gguf")?.variant_id ??
    variants[0]?.variant_id ??
    "";
  const backends = new Set(
    variants.flatMap((variant) => variant.compatible_backends ?? []),
  );
  model.runtime = {
    ...model.runtime,
    preferred_backend: backends.has("mlx")
      ? "device-selected"
      : model.runtime?.preferred_backend ?? "llama.cpp",
    compatible_backends: [...backends],
  };
  if (backends.has("mlx")) {
    model.display ??= {};
    model.display.badges = [...new Set([...(model.display.badges ?? []), "MLX"])];
  }
}

catalog.schema_version = "1.2.0";
catalog.catalog_version = "2026.07.27";
catalog.generated_at = new Date().toISOString();
catalog.catalog_policy.model_count = catalog.models.length;
catalog.catalog_policy.primary_format = "GGUF and MLX";
catalog.catalog_policy.download_policy =
  "Only existing public publisher artifacts are listed. Erebrus does not convert or republish weights.";
catalog.catalog_policy.integrity_policy =
  "Every downloadable file is pinned to an immutable repository revision with exact byte size and SHA-256.";
catalog.catalog_policy.provenance_policy =
  "Each variant identifies whether it is publisher-official or a community conversion and names its source repository.";

await writeFile(outputPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(
  `Wrote ${catalog.models.length} models and ${catalog.models.reduce(
    (sum, model) => sum + model.variants.length,
    0,
  )} variants to ${outputPath}`,
);
