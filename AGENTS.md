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
- Use Python 3.12 and `uv`.
- Local development uses a repository-local `.venv`.
- Docker images install dependencies from `uv.lock` into the container
  environment.
- Runtime hosts such as `aws-demo` and `dev-demo` should not manage Python
  dependencies directly.
- Default backend stack decisions should be encoded in bootstrap-generated
  project files where practical, because FastAPI does not provide a single
  official starter equivalent to `create-next-app`.
- Prefer async FastAPI with SQLAlchemy async, asyncpg, Alembic,
  Pydantic Settings, pytest/httpx/pytest-asyncio, and Ruff as the default
  Python backend shape.
- Prefer bearer-token authentication as the default API authentication shape.
  Keep the exact identity provider, OAuth flow, or token issuer configurable
  until real clients require a specific integration.
- Prefer standard-library `logging` with structured, request-aware log records
  as the initial logging baseline. Add heavier logging frameworks only when
  the application has a concrete need for them.

## Deployment Rules

- Deployment is manual only.
- Deployment must be performed with shell scripts only.
- Runtime deployment must use Docker.
- Docker images are built locally only.
- Do not build Docker images from this repository working tree.
- For Docker builds, clone the repository into a separate build location and
  build from that clean clone.
- The local build clone root is `J:\deploy_remote_repo`.
- Shell scripts running from WSL should refer to that build clone root as
  `/mnt/j/deploy_remote_repo`.
- A separate local clone may also be used for source preparation, local Docker
  image builds, migrations, or seed commands.
- Do not use a persistent local Uvicorn process as the normal development
  server path; validate the running application on `dev-demo` through Docker.
- A PostgreSQL container may run beside a separate local clone only as optional
  disposable development infrastructure.
- Export the built image to a `.tar` file locally.
- Transfer the image tarball to the target host, such as `aws-demo` or
  `dev-demo`.
- Load and run the image on the target host with explicit Docker commands or
  shell scripts.
- Keep deployment scripts target-specific. Use separate scripts for `aws-demo`
  and `dev-demo`, or separate target wrappers around shared conservative logic.
- Prepare target env files before deploying PostgreSQL or the app.
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
- `aws-demo` env setup scripts may create directories and template files, but
  must not generate or overwrite production-like secrets.
- `dev-demo` env setup scripts may generate development-only credentials, but
  must preserve existing env files.

## Operational Assumptions

- The production-like target is the `aws-demo` instance.
- The development server target is the `dev-demo` instance.
- `dev-demo` currently maps to the SSH alias `yoga` on the trusted LAN at
  `hchjeong@192.168.0.104`.
- The sibling applications and this backend may communicate through Docker
  networking or explicit host/port configuration, depending on deployment
  scripts.
- The local development PostgreSQL instance, if used, is not authoritative and
  must not be confused with the `aws-demo` PostgreSQL instance.
- `aws-demo` PostgreSQL should not publish a host port by default.
- `dev-demo` PostgreSQL may publish `192.168.0.104:5432` for trusted LAN
  development access.
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
- Leave app deployment scripts minimal until the app skeleton, Dockerfile,
  health endpoint, snippet endpoint, and image tag strategy are decided.
- Future app deployment scripts should consume a prebuilt local image tarball,
  load it on the target host, replace only the app container, and verify health.
- Clearly encode the target host in script names or target config files to
  reduce accidental cross-environment deployment.
