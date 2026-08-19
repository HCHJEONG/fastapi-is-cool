# Project Notes

This repository is for a shared backend server implemented with FastAPI and
Uvicorn.

The backend is intended to be used by sibling repositories, including:

- `global-ai-pricing`
- `legacy-lang-intelligence`
- `semantic-layer-explore`

These applications are deployed as Docker containers on remote instances. The
production-like target is reachable through the SSH host alias `aws-demo`; the
development server target is reachable through the SSH host alias `dev-demo`.

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
- A separate local clone may also be used as a development server workspace.
- A PostgreSQL container may run beside that separate local clone for local
  development, but it must be treated as a development database only.
- Export the built image to a `.tar` file locally.
- Transfer the image tarball to the target host, such as `aws-demo` or
  `dev-demo`.
- Load and run the image on the target host with explicit Docker commands or
  shell scripts.
- Keep deployment scripts target-specific. Use separate scripts for `aws-demo`
  and `dev-demo`, or separate target wrappers around shared conservative logic.
- The FastAPI/Uvicorn container and the PostgreSQL container must have separate
  lifecycles. Frequent application redeploys must not recreate or reset the
  database container.
- `aws-demo` scripts must preserve persistent state.
- `dev-demo` scripts may include development-only reset or recreate workflows,
  but they must never reuse `aws-demo` paths, credentials, volumes, or SSH host
  aliases.

## Secrets And Runtime Files

- Never include environment variable files in Docker images.
- Never include credentials or secret files in Docker images.
- Keep database files and other persistent runtime files outside containers.
- Keep local development PostgreSQL data outside this repository and outside
  Docker images.
- On `aws-demo`, create dedicated root-level directories for service-owned
  runtime files, databases, uploads, logs, and similar persistent data.
- On `dev-demo`, use separate dedicated directories from `aws-demo`, even when
  the directory layout is intentionally similar.
- Mount required runtime files or directories into containers at run time.
- Keep `aws-demo` PostgreSQL data in a dedicated host directory and manage it
  independently from app image replacement.

## Operational Assumptions

- The production-like target is the `aws-demo` instance.
- The development server target is the `dev-demo` instance.
- The sibling applications and this backend may communicate through Docker
  networking or explicit host/port configuration, depending on deployment
  scripts.
- The local development PostgreSQL instance, if used, is not authoritative and
  must not be confused with the `aws-demo` PostgreSQL instance.
- PostgreSQL should normally use an official Docker image and persistent host
  volumes, while the FastAPI/Uvicorn image is built from this codebase.
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
- App deployment scripts must not stop, remove, or recreate PostgreSQL unless
  the script is explicitly dedicated to database administration.
- Clearly encode the target host in script names or target config files to
  reduce accidental cross-environment deployment.
