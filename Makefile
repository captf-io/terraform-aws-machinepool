# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Every check for the aws machinepool module, which is the root of this
# repository. `make help` lists the targets; CONVENTIONS.md section 15 says
# what each one enforces.
#
# The host needs make, podman (or docker with ENGINE=docker), jq and Go (for
# tfcapi-lint). Every other tool runs in a container pinned by digest, as the
# host user, with the repository mounted at /work; nothing in the repository
# is left owned by root. Targets run serially, because the provider caches
# under .cache/ are not safe for concurrent writers; `make verify` runs
# independent groups side by side instead (see the verify target).

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.NOTPARALLEL:

# ---- Variables: override on the command line, e.g. `make validate RUNTIMES=opentofu`.

# Fixed per repository.
CLOUD := aws
ROLE := machinepool
ENGINE ?= podman
RUNTIMES ?= terraform opentofu

# tfcapi-lint is built from the provider repository (public; CI checks it out
# into .cache/provider). TFCAPI_LINT names a ready binary instead. Without
# either, the target skips.
PROVIDER_DIR ?= ../cluster-api-provider-terraform
TFCAPI_LINT ?=
TFCAPI_LINT_BIN := .tools/bin/tfcapi-lint

# Warnings tfcapi-lint is allowed to emit, as full flags:
#   TFCAPI_LINT_ALLOW := --allow-warning <id> --allow-warning <id>
# Put the reason in a comment above the assignment AND in the README's
# "Exceptions" section (CONVENTIONS.md section 15). None so far.
TFCAPI_LINT_ALLOW :=

# Runtime images, pinned by digest: the CAPTF base images the module images
# build FROM, so the checks run on the runtimes the module ships with. The
# floors are the oldest runtimes the module supports.
TF_IMAGE_terraform := ghcr.io/captf-io/terraform-base:1.16.5@sha256:974c18d5fbbbf1701bdc060b8c3838934cb4780ceb1683207ae43e48573f94e2
TF_IMAGE_opentofu := ghcr.io/captf-io/opentofu-base:1.12.7@sha256:eb9c589b3036f4e0914b56969c84b11ce50ea1527f49bddfb8896531547ba798
TF_FLOOR_terraform := docker.io/hashicorp/terraform:1.5.7@sha256:9fc0d70fb0f858b0af1fadfcf8b7510b1b61e8b35e7a4bb9ff39f7f6568c321d
TF_FLOOR_opentofu := ghcr.io/opentofu/opentofu:1.6.3@sha256:bcfdb7fcd385eb62c3389f7b06f5813de55d09d709498fbb5421dcc6dd4c3d06
# Terraform 1.5 ignores *.tftest.hcl. OpenTofu 1.6 reads them at init and
# fails on mock_provider (OpenTofu 1.8+), so its floor runs on a staged copy
# without tests/ (NO_TESTS=1; `validate -no-tests` is too late, init fails).
TF_FLOOR_NO_TESTS_terraform :=
TF_FLOOR_NO_TESTS_opentofu := 1
TFLINT_IMAGE := ghcr.io/terraform-linters/tflint:v0.64.0@sha256:1c595f42d794c32c45a6ea8b58655fd66433d4ca3b1bc631c574a48d120bd19f
TRIVY_IMAGE := docker.io/aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa
SHELLCHECK_IMAGE := docker.io/koalaman/shellcheck-alpine:v0.11.0@sha256:9955be09ea7f0dbf7ae942ac1f2094355bb30d96fffba0ec09f5432207544002
LICENSE_EYE_IMAGE := docker.io/apache/skywalking-eyes:0.9.0@sha256:cd89ccbbcba2e87d3fb0e34b156b1da208d6c5ac1ada4e2d335e920022c765b8

ifeq ($(ENGINE),docker)
USER_FLAGS := --user $(shell id -u):$(shell id -g)
else
USER_FLAGS := --userns=keep-id --user $(shell id -u):$(shell id -g)
endif
# A container with the repository at /work, as the host user.
CONTAINER = $(ENGINE) run --rm $(USER_FLAGS) --security-opt label=disable \
	-e HOME=/tmp -v "$(CURDIR):/work" -w /work

# hack/tf-run.sh reads the pins for `default` from these.
export ENGINE TF_IMAGE_terraform TF_IMAGE_opentofu

# Build $(TFCAPI_LINT_BIN) from the provider repository unless TFCAPI_LINT is
# set; leave `bin` empty when neither is available.
define RESOLVE_TFCAPI_LINT
bin='$(TFCAPI_LINT)'; \
if [ -z "$$bin" ] && [ -d '$(PROVIDER_DIR)/cmd/tfcapi-lint' ]; then \
	mkdir -p .tools/bin; \
	(cd '$(PROVIDER_DIR)' && go build -o '$(CURDIR)/$(TFCAPI_LINT_BIN)' ./cmd/tfcapi-lint); \
	bin='$(CURDIR)/$(TFCAPI_LINT_BIN)'; \
fi
endef

.PHONY: help fmt fmt-check validate unit-test tflint tfcapi-lint scan \
	shellcheck check-conventions check-headers fix-headers verify clean

help: ## Show targets.
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "%-18s %s\n", $$1, $$2}'
	@echo
	@echo "CLOUD=$(CLOUD) ROLE=$(ROLE) RUNTIMES=$(RUNTIMES) ENGINE=$(ENGINE)"

fmt: ## Format the module with terraform fmt and tofu fmt, in place.
	@for rt in $(RUNTIMES); do hack/tf-run.sh fmt "$$rt" default; done

fmt-check: ## Fail on any file terraform fmt or tofu fmt would change.
	@for rt in $(RUNTIMES); do hack/tf-run.sh fmt-check "$$rt" default; done

validate: ## init + validate on both runtimes and on their floors (Terraform 1.5.7, OpenTofu 1.6.3).
	@for rt in $(RUNTIMES); do \
		hack/tf-run.sh validate "$$rt" default; \
		case "$$rt" in \
			terraform) NO_TESTS=$(TF_FLOOR_NO_TESTS_terraform) hack/tf-run.sh validate "$$rt" "$(TF_FLOOR_terraform)" ;; \
			opentofu) NO_TESTS=$(TF_FLOOR_NO_TESTS_opentofu) hack/tf-run.sh validate "$$rt" "$(TF_FLOOR_opentofu)" ;; \
		esac; \
	done

unit-test: ## terraform test / tofu test (mocked providers); skips when there is no tests/.
	@if [ -z "$$(find tests -name '*.tftest.hcl' -print -quit 2>/dev/null)" ]; then \
		echo "unit-test: no tests/*.tftest.hcl: skipped"; exit 0; \
	fi; \
	for rt in $(RUNTIMES); do hack/tf-run.sh test "$$rt" default; done

tflint: ## tflint with the terraform ruleset (preset all) and the cloud ruleset, per .tflint.hcl.
	@mkdir -p .cache/tflint; \
	$(CONTAINER) -e TFLINT_PLUGIN_DIR=/work/.cache/tflint $(if $(GITHUB_TOKEN),-e GITHUB_TOKEN) \
		"$(TFLINT_IMAGE)" --init --config /work/.tflint.hcl; \
	$(CONTAINER) -e TFLINT_PLUGIN_DIR=/work/.cache/tflint \
		"$(TFLINT_IMAGE)" --config /work/.tflint.hcl --chdir /work

tfcapi-lint: ## tfcapi-lint module --strict (builds it from PROVIDER_DIR; skips when absent).
	@$(RESOLVE_TFCAPI_LINT); \
	if [ -z "$$bin" ]; then \
		echo "SKIP tfcapi-lint: neither TFCAPI_LINT nor $(PROVIDER_DIR)/cmd/tfcapi-lint is available"; exit 0; \
	fi; \
	"$$bin" module --role "$(ROLE)" --strict $(TFCAPI_LINT_ALLOW) .

scan: ## trivy config over the repository (HCL, workflows); ignores live in .trivyignore.yaml.
	@mkdir -p .cache/trivy; \
	$(CONTAINER) -e TRIVY_CACHE_DIR=/work/.cache/trivy "$(TRIVY_IMAGE)" config \
		--exit-code 1 --severity MEDIUM,HIGH,CRITICAL \
		--ignorefile .trivyignore.yaml \
		--skip-dirs build --skip-dirs .cache --skip-dirs .tools --skip-dirs hack/testdata .

check-conventions: ## hack/check-layout.sh (CONVENTIONS.md sections 2, 4) and hack/check-tags.sh (section 7).
	@hack/check-layout.sh --self-test
	@hack/check-layout.sh
	@hack/check-tags.sh

shellcheck: ## shellcheck over hack/ and every shell template, rendered with placeholders (hack/check-shell.sh).
	@SHELLCHECK_IMAGE='$(SHELLCHECK_IMAGE)' hack/check-shell.sh

check-headers: ## Fail on any source file without the Apache-2.0 license header (.licenserc.yaml).
	@$(CONTAINER) "$(LICENSE_EYE_IMAGE)" header check

fix-headers: ## Add the Apache-2.0 license header to every source file missing it.
	@$(CONTAINER) "$(LICENSE_EYE_IMAGE)" header fix

# verify runs three groups at the same time and prints each group's log in
# turn: the static checks, and one group per runtime that runs validate and
# unit-test for it (the slow ones). The groups share no writable path: a
# runtime has its own plugin cache (.cache/plugins/<runtime>) and stage
# (build/stage/<runtime>-*), tflint and trivy have their own caches, and
# check-conventions renders the Terraform schema, so it runs in the Terraform
# group (or in the static one when Terraform is not in RUNTIMES). Inside a
# group the targets still run serially (.NOTPARALLEL).
verify: ## Everything above, in parallel groups: static checks, then one group per runtime.
	@set -u; log=$$(mktemp -d); trap 'rm -rf -- "$$log"' EXIT; \
	static='check-headers fmt-check shellcheck tflint tfcapi-lint scan'; \
	case " $(RUNTIMES) " in *" terraform "*) ;; *) static="$$static check-conventions" ;; esac; \
	names=(static); \
	$(MAKE) --no-print-directory $$static >"$$log/static.log" 2>&1 & pids=($$!); \
	for rt in $(RUNTIMES); do \
		names+=("$$rt"); \
		goals='validate unit-test'; [ "$$rt" != terraform ] || goals="check-conventions $$goals"; \
		$(MAKE) --no-print-directory RUNTIMES="$$rt" $$goals >"$$log/$$rt.log" 2>&1 & pids+=($$!); \
	done; \
	rc=0; \
	for i in "$${!pids[@]}"; do \
		if wait "$${pids[$$i]}"; then st=ok; else st=FAILED; rc=1; fi; \
		echo "===== verify: $${names[$$i]}: $$st"; cat "$$log/$${names[$$i]}.log"; \
	done; \
	[ $$rc -eq 0 ] || { echo "verify: FAILED"; exit 1; }; \
	echo "verify: ok"

clean: ## Remove build/ (staged module, schemas). Keeps .cache/ (providers) and .tools/.
	@d='$(CURDIR)/build'; \
	if [ -d "$$d" ] && [ ! -L "$$d" ] && [ -f '$(CURDIR)/Makefile' ] && [ "$$d" = "$$(cd '$(CURDIR)' && pwd -P)/build" ]; then \
		echo "clean: removing $$d"; rm -rf -- "$$d"; \
	else \
		echo "clean: no build/ to remove"; \
	fi

print-%: ## Print a variable, e.g. `make print-ROLE`.
	@printf '%s\n' '$($*)'
