# Implementation Plan

## Deployment Model

- Manage two Docker containers from this repository:
  - FastAPI/Uvicorn application container.
  - PostgreSQL database container.
- Keep their lifecycles separate.
- The application container is expected to change frequently.
- The PostgreSQL container is expected to be created rarely and preserved across
  application redeploys.
- Maintain target-specific deployment scripts for:
  - `aws-demo`
  - `dev-demo`
- Prefer explicit script names or target wrappers so the deployment destination
  is visible before execution.

## Python And Dependency Management

- Use Python 3.12.
- Use `uv` for dependency and virtual environment management.
- Local development uses a repository-local `.venv`.
- Commit `pyproject.toml` and `uv.lock`.
- Docker images install dependencies from `uv.lock` into the container
  environment.
- Runtime hosts such as `aws-demo` and `dev-demo` should not manage Python
  dependencies directly.

## Local Development Database

- A separate local clone may be used as the development server workspace.
- A local PostgreSQL container may run beside that separate clone.
- Local PostgreSQL data must live outside this repository.
- Local PostgreSQL credentials and env files must not be committed or included
  in Docker images.
- The local PostgreSQL instance is disposable development infrastructure, not
  the authoritative production-like database.

## Remote Database On aws-demo

- The `aws-demo` PostgreSQL container should be managed separately from app
  deployment.
- Use a dedicated root-level host directory for PostgreSQL data.
- Use remote-only env files or mounted secret files.
- App redeploy scripts must not stop, remove, or recreate the PostgreSQL
  container.
- Database backup and restore should be handled by explicit database scripts.

## Remote Database On dev-demo

- The `dev-demo` PostgreSQL container should use its own data directories,
  env files, volumes, container names, and Docker network names.
- `dev-demo` may support development-only reset or recreate scripts.
- `dev-demo` scripts must never reference `aws-demo` credentials, directories,
  volumes, or SSH host aliases.
- Keep `dev-demo` close enough to `aws-demo` to test deployment behavior, while
  allowing controlled destructive workflows that would be unsafe on `aws-demo`.

## Initial Script Shape

- `deploy-app-aws-demo.sh`
- `deploy-app-dev-demo.sh`
- `deploy-postgres-aws-demo.sh`
- `deploy-postgres-dev-demo.sh`
- `backup-postgres-aws-demo.sh`
- `reset-postgres-dev-demo.sh`
