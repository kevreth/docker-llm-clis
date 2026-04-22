# Exported Container Runtime Requirements

This directory contains the files needed to start the exported `docker-llm-cli` container with `./run.sh`.

## Prerequisites

- Docker must be installed and available on your host as the `docker` command.
- The `docker-llm-cli` image must already exist locally. For example, load it first with:

```bash
docker load -i docker-llm-cli.tar
```

- A host workspace directory must exist. It will be mounted into the container at `/workspace`.
- If you need provider access inside the container, the corresponding API credentials must be available in `docker-llm-cli.env`.

## Required Environment Configuration

`run.sh` reads `docker-llm-cli.env` from this directory and refuses to start unless:

- `docker-llm-cli.env` exists
- `docker-llm-cli.env` has permissions `600`
- `WORKSPACE_DIR` is set
- `WORKSPACE_DIR` points to an existing directory on the host

Example:

```bash
chmod 600 docker-llm-cli.env
```

Set `WORKSPACE_DIR` to the host directory you want mounted into the container:

```bash
WORKSPACE_DIR=/absolute/path/to/your/project
```

Inside the container, that directory is available at `/workspace`.

## Optional API and Auth Environment Variables

Only non-empty variables from `docker-llm-cli.env` are forwarded into the container. Leave unused values blank.

Common optional variables include:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `GROQ_API_KEY`
- `MISTRAL_API_KEY`
- `OPENROUTER_API_KEY`
- `KIMI_API_KEY`
- `CEREBRAS_API_KEY`
- `MINIMAX_API_KEY`
- `IONET_API_KEY`
- `VERCEL_API_KEY`
- `ZAI_API_KEY`
- `HF_TOKEN`
- `CLAUDE_CODE_OAUTH_TOKEN`

Additional optional integrations supported by the env file include:

- AWS Bedrock: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_PROFILE`, `AWS_BEARER_TOKEN_BEDROCK`
- Azure OpenAI: `AZURE_OPENAI_API_ENDPOINT`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_API_VERSION`
- Vertex AI: `VERTEXAI_PROJECT`, `VERTEXAI_LOCATION`

## Runtime Notes

- `run.sh` starts the container with `docker run`.
- The host `WORKSPACE_DIR` is bind-mounted to `/workspace`.
- Docker named volumes are used for `/artifacts` and `/home/llm`.
- If `SSH_AUTH_SOCK` is available on the host, it is mounted for git/SSH usage inside the container.

## Start

```bash
./run.sh
```
