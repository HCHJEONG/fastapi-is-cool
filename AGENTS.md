# Project Notes

This repository is for a shared backend server implemented with FastAPI and
Uvicorn.

The backend is intended to be used by sibling repositories, including:

- `global-ai-pricing`
- `legacy-lang-intelligence`
- `semantic-layer-explore`

These applications are deployed as Docker containers on the same remote
instance, reachable through the SSH host alias `aws-demo`.

## Development Direction

- Build the backend as a shared service for the sibling applications.
- Prefer simple, explicit FastAPI APIs over framework-heavy abstractions.
- Keep runtime configuration external to the image.
- Treat local development, local Docker image creation, and remote deployment
  as separate steps.

## Deployment Rules

- Deployment is manual only.
- Deployment must be performed with shell scripts only.
- Runtime deployment must use Docker.
- Docker images are built locally only.
- Do not build Docker images from this repository working tree.
- For Docker builds, clone the repository into a separate build location and
  build from that clean clone.
- Export the built image to a `.tar` file locally.
- Transfer the image tarball to `aws-demo`.
- Load and run the image on `aws-demo` with explicit Docker commands or shell
  scripts.

## Secrets And Runtime Files

- Never include environment variable files in Docker images.
- Never include credentials or secret files in Docker images.
- Keep database files and other persistent runtime files outside containers.
- On `aws-demo`, create dedicated root-level directories for service-owned
  runtime files, databases, uploads, logs, and similar persistent data.
- Mount required runtime files or directories into containers at run time.

## Operational Assumptions

- The production-like target is the single `aws-demo` instance.
- The sibling applications and this backend may communicate through Docker
  networking or explicit host/port configuration, depending on deployment
  scripts.
- Scripts should make paths, image names, container names, ports, volumes, and
  env-file locations easy to inspect before execution.

## Agent Guidance

- Do not add automated deployment systems, CI/CD deployment flows, hosted build
  steps, or registry-based deployment unless explicitly requested.
- Do not assume credentials can be committed, copied into images, or generated
  into the repository.
- When adding scripts, keep them readable and conservative.
- When changing Docker behavior, preserve the local-build, tar-transfer,
  remote-run workflow.
