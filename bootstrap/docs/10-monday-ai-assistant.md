# Monday — Local AI Assistant (Ollama + Open WebUI)

Monday is a locally-running AI assistant deployed on the K3s cluster using Ollama as the LLM backend and Open WebUI as the chat interface.

## Access

**Chat UI:** http://monday.cluster.local

## First-Time Model Pull

Ollama starts with no models loaded. After the first deploy, pull a model:

```bash
kubectl exec -n monday deploy/ollama -- ollama pull gemma3:1b
```

Recommended models for this hardware (Pi 4, ~1.5GB headroom):

| Model | RAM usage | Quality |
|-------|-----------|---------|
| `gemma3:1b` | ~800Mi | Good for general chat |
| `qwen2.5:1.5b` | ~1Gi | Good reasoning |
| `llama3.2:1b` | ~1.3Gi | Tight but workable |

> Only pull one model at a time. The 10Gi PVC fits 2–3 small models.

## Checking Status

```bash
kubectl -n monday get pods
kubectl -n monday logs deploy/ollama
kubectl -n monday logs deploy/open-webui
```

## Listing Loaded Models

```bash
kubectl exec -n monday deploy/ollama -- ollama list
```

## Memory Note

Ollama keeps the loaded model in memory for 5 minutes after the last request (`OLLAMA_KEEP_ALIVE=5m`), then unloads it. Set to `0` to unload immediately if memory pressure is an issue.

## Architecture

- Both services pinned to `pi4controller` via `nodeSelector`
- Ollama API is ClusterIP only (not externally exposed)
- Open WebUI exposed via Traefik at `monday.cluster.local`
- Longhorn PVCs: Ollama 10Gi (models), Open WebUI 2Gi (chat history)
- Managed by ArgoCD via `cluster/argocd/workloads/monday.yaml`
