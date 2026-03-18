---
description: buf proto codegen 실행, 생성 파일 diff 확인, 변경 시 커밋 제안
allowed-tools: Bash(bash:*), Bash(git:*), Bash(cat:*), Bash(ls:*)
---

## Context

- codegen script: !`ls /home/choih/works/ih-scratch/deepspan/scripts/codegen.sh`
- buf version: !`buf --version 2>/dev/null || echo "buf not found"`
- buf plugins (local): !`ls /home/choih/goes/bin/protoc-gen-go /home/choih/goes/bin/protoc-gen-connect-go 2>/dev/null || which protoc-gen-go protoc-gen-connect-go 2>/dev/null || echo "plugins not found"`
- Current gen/go diff: !`git -C /home/choih/works/ih-scratch/deepspan diff --stat gen/go/ 2>/dev/null`
- proto files: !`find /home/choih/works/ih-scratch/deepspan/proto -name "*.proto" 2>/dev/null`

## Your task

Protobuf codegen을 실행하고 결과를 검증하세요.

### 절차

1. **환경 확인**:
   - `buf` 설치 확인
   - `protoc-gen-go`, `protoc-gen-connect-go` local 플러그인 확인
   - 없으면 설치 방법 안내:
     ```bash
     go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
     go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest
     ```

2. **실행**:
   ```bash
   cd /home/choih/works/ih-scratch/deepspan
   bash scripts/codegen.sh
   ```

3. **변경 확인**:
   ```bash
   git diff --stat gen/go/
   git diff gen/go/
   ```

4. **결과 분류**:
   - 변경 없음: "proto와 gen 코드가 동기화됨" 출력
   - 변경 있음:
     - 변경 내용 요약 (어떤 메시지/서비스가 바뀌었는지)
     - 서버/mgmt-daemon 컴파일 영향 확인
     - 커밋 여부 물어보기

5. **커밋 시** (`build(proto): regenerate Go stubs` 형식 사용):
   ```bash
   git add gen/go/
   git commit -m "build(proto): regenerate Go stubs"
   ```

### 주의사항
- `buf.gen.yaml`은 `local:` 플러그인 사용 (remote 플러그인 아님)
- gen/python/ 은 .gitignore에서 제외됨 (커밋 불필요)
- codegen 후 server/mgmt-daemon go build 확인 권장
