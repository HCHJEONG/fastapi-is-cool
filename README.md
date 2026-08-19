# fastapi-is-cool

이 레포는 FastAPI 백엔드의 기본 뼈대와 수동 Docker 배포 절차를
반복 가능하게 만들기 위한 프로젝트입니다.

목표는 단순합니다. 어떤 사용자가 이 레포를 `git clone`한 뒤 shell
스크립트를 순서대로 실행하면 다음까지 도달할 수 있어야 합니다.

- FastAPI 앱 skeleton 생성
- PostgreSQL 기반 baseline DB 준비
- Alembic migration 실행
- seed 데이터 입력
- Docker image build/export
- dev-demo 또는 aws-demo에 app container 배포
- 마지막에 `curl`로 JSON 응답 확인

초기 API와 `content_snippets` 테이블은 실제 도메인 모델이라기보다
배포 경로 검증용 baseline입니다. 이 baseline이 동작하는 것을 확인한
뒤, 원하는 DB schema, migration, service, API route를 추가하면 됩니다.

## 사전 준비

로컬 머신에는 다음이 필요합니다.

- Git
- WSL 또는 Linux shell 환경
- OpenSSH client
- `uv`
- `uv`가 찾을 수 있는 Python 3.12
- Docker image를 빌드할 수 있는 Docker 환경

Windows 사용자는 보통 WSL 안에서 이 레포를 다루는 것을 전제로 합니다.

원격 host에는 다음이 필요합니다.

- `dev-demo`: SSH 접속 가능, Docker 실행 가능
- `aws-demo`: SSH 접속 가능, `sudo docker` 실행 가능

기본 개인 환경은 다음 값을 전제로 합니다.

```sh
DEV_DEMO_HOST=yoga
DEV_DEMO_LAN_IP=192.168.0.104
AWS_DEMO_HOST=aws-demo
BUILD_CLONE_ROOT_WSL=/mnt/j/deploy_remote_repo
```

다른 환경에서는 `scripts/env/*.env` 파일을 수정하면 됩니다.

## 로컬 환경 설정 파일

커밋되는 예시 파일은 다음입니다.

```sh
scripts/env/dev-demo.local.env.example
scripts/env/aws-demo.local.env.example
```

개인 설정 파일은 gitignore 됩니다.

```sh
scripts/env/dev-demo.env
scripts/env/aws-demo.env
```

처음 clone한 사용자는 필요하면 예시 파일을 복사해서 자기 환경에 맞게
수정합니다.

```sh
cp scripts/env/dev-demo.local.env.example scripts/env/dev-demo.env
cp scripts/env/aws-demo.local.env.example scripts/env/aws-demo.env
```

이 레포에는 현재 작성자의 개인 기본값이 `scripts/env/*.env`에 들어가
있지만, 이 파일들은 gitignore 대상입니다.

## J 드라이브와 clean clone 위치

Docker image는 현재 작업 트리에서 직접 빌드하지 않습니다. 대신 별도의
clean clone에서 빌드합니다.

기본값은 다음입니다.

```sh
BUILD_CLONE_ROOT_WINDOWS=J:\\deploy_remote_repo
BUILD_CLONE_ROOT_WSL=/mnt/j/deploy_remote_repo
BUILD_ARTIFACT_DIR_WSL=/mnt/j/deploy_remote_repo/artifacts
```

J 드라이브가 WSL에서 `/mnt/j`로 보이면, `J:\deploy_remote_repo` 폴더가
아직 없어도 build script가 clone 과정에서 만들 수 있습니다.

단, J 드라이브 자체가 없거나 WSL에 `/mnt/j`로 마운트되어 있지 않다면
자동으로 해결할 수 없습니다. 그런 경우 `scripts/env/dev-demo.env`와
`scripts/env/aws-demo.env`에서 `BUILD_CLONE_ROOT_WSL`과
`BUILD_ARTIFACT_DIR_WSL`을 실제 사용 가능한 경로로 바꾸세요.

예:

```sh
BUILD_CLONE_ROOT_WSL=$HOME/deploy_remote_repo
BUILD_ARTIFACT_DIR_WSL=$HOME/deploy_remote_repo/artifacts
```

## 전체 실행 순서

각 스크립트는 성공하면 다음에 실행할 스크립트를 안내합니다. 그래서
아래 순서를 외우지 않아도 됩니다. 그래도 전체 흐름은 다음과 같습니다.

### 1. 사전 점검

```sh
scripts/check-prereqs.sh
```

로컬 명령, Python 3.12, SSH, 원격 Docker 접근 가능 여부를 확인합니다.
실패한 항목이 있으면 먼저 고칩니다.

### 2. 로컬 Python 환경 생성

```sh
scripts/bootstrap/setup-local-venv.sh
```

생성되는 것:

- `.venv`
- `pyproject.toml`
- `uv.lock`

### 3. FastAPI skeleton 생성

```sh
scripts/bootstrap/create-app-skeleton.sh
```

생성되는 것:

- `app/`
- `alembic/`
- `tests/`
- `alembic.ini`
- baseline health/snippet API
- baseline migration/seed 코드

생성 후에는 commit/push가 필요합니다. clean clone에서 Docker image를
빌드하기 때문입니다.

```sh
git status --short
git add pyproject.toml uv.lock app alembic alembic.ini tests
git commit -m "Bootstrap FastAPI baseline"
git push
```

## dev-demo 경로

내부망에서 작업 중이면 dev-demo를 먼저 검증하는 것을 권장합니다.

```sh
scripts/dev-demo/setup-env.sh
scripts/dev-demo/deploy-postgres.sh
scripts/dev-demo/alembic.sh upgrade
scripts/dev-demo/seed-content-snippets.sh
scripts/build/build-image-tar.sh
IMAGE_TAR="/mnt/j/deploy_remote_repo/artifacts/fastapi-is-cool-<sha>.tar" scripts/dev-demo/deploy-app.sh
```

`deploy-app.sh`가 성공하면 마지막에 다음과 같은 검증 명령을 출력합니다.

```sh
curl http://192.168.0.104:8000/health
curl http://192.168.0.104:8000/api/v1/snippets/home.hero
```

OpenAPI 명세 파일이 필요하면 실행 중인 FastAPI 앱에서 export합니다.
생성된 `scripts/openapi/openapi.json`은 git에 포함하지 않습니다.

```sh
OPENAPI_URL="http://192.168.0.104:8000/openapi.json" scripts/export-openapi.sh
```

기대 응답 예:

```json
{"status":"ok"}
```

snippet 응답은 timestamp를 포함합니다.

```json
{
  "key": "home.hero",
  "title": "Home Hero",
  "body": "FastAPI is cool.",
  "created_at": "...",
  "updated_at": "..."
}
```

## 내부망 밖에서 작업하는 경우

공유기 내부망 밖에서 배포를 진행한다면 dev-demo 경로 전체를 건너뛸 수
있습니다. dev-demo의 PostgreSQL은 내부망 접근을 전제로 하므로,
내부망 밖에서는 다음 스크립트들을 실행하지 않는 편이 자연스럽습니다.

```sh
scripts/dev-demo/setup-env.sh
scripts/dev-demo/deploy-postgres.sh
scripts/dev-demo/alembic.sh upgrade
scripts/dev-demo/seed-content-snippets.sh
scripts/dev-demo/deploy-app.sh
```

이 경우에도 image tarball은 먼저 빌드합니다.

```sh
scripts/build/build-image-tar.sh
```

그 다음 바로 aws-demo 경로로 진행합니다.

```sh
scripts/aws-demo/setup-env.sh
scripts/aws-demo/deploy-postgres.sh
IMAGE_TAR="/mnt/j/deploy_remote_repo/artifacts/fastapi-is-cool-<sha>.tar" scripts/aws-demo/alembic.sh upgrade
IMAGE_TAR="/mnt/j/deploy_remote_repo/artifacts/fastapi-is-cool-<sha>.tar" scripts/aws-demo/seed-content-snippets.sh
IMAGE_TAR="/mnt/j/deploy_remote_repo/artifacts/fastapi-is-cool-<sha>.tar" scripts/aws-demo/deploy-app.sh
```

## aws-demo 경로

aws-demo는 production-like 대상입니다. PostgreSQL host port를 공개하지
않고, app container와 DB container가 Docker network 안에서 통신합니다.

aws-demo env 파일은 자동으로 production-like secret을 생성하지 않습니다.
`scripts/aws-demo/setup-env.sh`가 원격 host에 example 파일을 만들면,
사용자가 직접 `/srv/fastapi-is-cool/env/postgres.env`와
`/srv/fastapi-is-cool/env/app.env`를 준비해야 합니다.

aws-demo app 배포는 다음을 수행합니다.

- prebuilt image tarball 전송
- `sudo docker load`
- 기존 app container만 교체
- PostgreSQL container는 건드리지 않음
- `/health` 확인
- 마지막에 `curl` 검증 명령 출력

성공 후 기본 검증은 aws-demo 인스턴스 안에서 `localhost`로 확인하는
방식입니다. 외부에서 8000 포트를 열지 않아도 이 검증은 가능합니다.

```sh
ssh aws-demo "curl -fsS http://127.0.0.1:8000/health"
ssh aws-demo "curl -fsS http://127.0.0.1:8000/api/v1/snippets/home.hero"
```

## 자주 막히는 지점

### `uv`가 Python 3.12를 못 찾는 경우

Python 3.12를 설치하거나 `uv`가 Python 3.12를 다운로드/사용할 수 있게
환경을 정리해야 합니다.

### build script가 commit/push를 요구하는 경우

정상입니다. Docker image는 현재 작업 트리가 아니라 clean clone에서
빌드합니다. 생성된 baseline 파일을 commit/push한 뒤 다시 실행하세요.

### `/mnt/j/deploy_remote_repo` 관련 오류

J 드라이브가 WSL에 `/mnt/j`로 보이는지 확인하세요.

```sh
ls /mnt/j
```

J 드라이브가 없다면 `scripts/env/*.env`에서 build clone 경로를 다른
위치로 바꾸세요.

### aws-demo에서 env 파일이 없다고 나오는 경우

정상적인 안전장치입니다. aws-demo는 production-like 대상이므로 script가
secret을 자동 생성하지 않습니다. 원격 host에서 example 파일을 보고
직접 env 파일을 준비하세요.

## 최종 성공 기준

최종 성공 기준은 aws-demo 인스턴스에서 app container가 응답하고,
aws-demo 내부 `localhost` 기준 curl에서 JSON 응답이 찍히는 것입니다.

```sh
ssh aws-demo "curl -fsS http://127.0.0.1:8000/health"
```

```json
{"status":"ok"}
```

그리고 seed된 snippet이 조회되어야 합니다.

```sh
ssh aws-demo "curl -fsS http://127.0.0.1:8000/api/v1/snippets/home.hero"
```

여기까지 되면 baseline backend 배포 경로는 완성된 것입니다. 그 다음부터
사용자는 자기 서비스에 필요한 DB schema, migration, API를 추가하면 됩니다.
