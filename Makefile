# Operator variables
# ==================
export APP_NAME=compliance-operator
RESULTSCOLLECTORBIN=resultscollector
RESULTSERVERBIN=resultserver
OPENSCAP_IMAGE_NAME=openscap-ocp
RESULTSCOLLECTOR_IMAGE_NAME=$(RESULTSCOLLECTORBIN)
RESULTSERVER_IMAGE_NAME=$(RESULTSERVERBIN)
REMEDIATION_AGGREGATORBIN=remediation-aggregator
REMEDIATION_AGGREGATOR_IMAGE_NAME=$(REMEDIATION_AGGREGATORBIN)

# Container image variables
# =========================
IMAGE_REPO?=quay.io/compliance-operator
RUNTIME?=podman

# Image path to use. Set this if you want to use a specific path for building
# or your e2e tests. This is overwritten if we bulid the image and push it to
# the cluster or if we're on CI.
OPERATOR_IMAGE_PATH?=$(IMAGE_REPO)/$(APP_NAME)
OPENSCAP_IMAGE_PATH=$(IMAGE_REPO)/$(OPENSCAP_IMAGE_NAME)
OPENSCAP_DOCKERFILE_PATH=./images/openscap/Dockerfile
RESULTSCOLLECTOR_IMAGE_PATH=$(IMAGE_REPO)/$(RESULTSCOLLECTOR_IMAGE_NAME)
RESULTSCOLLECTOR_DOCKERFILE_PATH=./images/resultscollector/Dockerfile
RESULTSERVER_IMAGE_PATH=$(IMAGE_REPO)/$(RESULTSERVER_IMAGE_NAME)
RESULTSERVER_DOCKERFILE_PATH=./images/resultserver/Dockerfile
REMEDIATION_AGGREGATOR_IMAGE_PATH=$(IMAGE_REPO)/$(REMEDIATION_AGGREGATOR_IMAGE_NAME)
REMEDIATION_AGGREGATOR_DOCKERFILE_PATH=./images/remediation-aggregator/Dockerfile

# Image tag to use. Set this if you want to use a specific tag for building
# or your e2e tests.
TAG?=latest

# Build variables
# ===============
CURPATH=$(PWD)
TARGET_DIR=$(CURPATH)/build/_output
GO=GOFLAGS=-mod=vendor GO111MODULE=auto go
GOBUILD=$(GO) build
BUILD_GOPATH=$(TARGET_DIR):$(CURPATH)/cmd
TARGET=$(TARGET_DIR)/bin/$(APP_NAME)
RESULTSCOLLECTOR_TARGET=$(TARGET_DIR)/bin/$(RESULTSCOLLECTORBIN)
RESULTSERVER_TARGET=$(TARGET_DIR)/bin/$(RESULTSERVERBIN)
AGGREAGATOR_TARGET=$(TARGET_DIR)/bin/$(REMEDIATION_AGGREGATORBIN)
MAIN_PKG=cmd/manager/main.go
PKGS=$(shell go list ./... | grep -v -E '/vendor/|/test|/examples')
# This is currently hardcoded to our most performance sensitive package
BENCHMARK_PKG?=github.com/openshift/compliance-operator/pkg/utils

# go source files, ignore vendor directory
SRC = $(shell find . -type f -name '*.go' -not -path "./vendor/*" -not -path "./_output/*")


# Kubernetes variables
# ====================
KUBECONFIG?=$(HOME)/.kube/config
export NAMESPACE?=openshift-compliance

# Operator-sdk variables
# ======================
SDK_VERSION?=v0.14.1
OPERATOR_SDK_URL=https://github.com/operator-framework/operator-sdk/releases/download/$(SDK_VERSION)/operator-sdk-$(SDK_VERSION)-x86_64-linux-gnu

# Test variables
# ==============
TEST_OPTIONS?=
# Skip pushing the container to your cluster
E2E_SKIP_CONTAINER_PUSH?=false

# Pass extra flags to the e2e test run.
# e.g. to run a specific test in the e2e test suite, do:
# 	make e2e E2E_GO_TEST_FLAGS="-v -run TestE2E/TestScanWithNodeSelectorFiltersCorrectly"
E2E_GO_TEST_FLAGS?=-v -timeout 120m

# operator-courier arguments for `make publish`.
# Before running `make publish`, install operator-courier with `pip3 install operator-courier` and create
# ~/.quay containing your quay.io token.
COURIER_CMD=operator-courier
COURIER_PACKAGE_NAME=compliance-operator-bundle
COURIER_OPERATOR_DIR=deploy/olm-catalog/compliance-operator
COURIER_QUAY_NAMESPACE=compliance-operator
COURIER_PACKAGE_VERSION?="0.1.0"
COURIER_QUAY_TOKEN?= $(shell cat ~/.quay)

.PHONY: all
all: build ## Test and Build the compliance-operator

.PHONY: help
help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


.PHONY: image
image: fmt operator-sdk operator-image resultscollector-image remediation-aggregator-image resultserver-image openscap-image ## Build the compliance-operator container image

.PHONY: operator-image
operator-image:
	$(GOPATH)/bin/operator-sdk build $(OPERATOR_IMAGE_PATH) --image-builder $(RUNTIME)

.PHONY: openscap-image
openscap-image:
	$(RUNTIME) build -f $(OPENSCAP_DOCKERFILE_PATH) -t $(OPENSCAP_IMAGE_PATH):$(TAG)

.PHONY: resultscollector-image
resultscollector-image:
	$(RUNTIME) build -f $(RESULTSCOLLECTOR_DOCKERFILE_PATH) -t $(RESULTSCOLLECTOR_IMAGE_PATH):$(TAG) .

.PHONY: resultserver-image
resultserver-image:
	$(RUNTIME) build -f $(RESULTSERVER_DOCKERFILE_PATH) -t $(RESULTSERVER_IMAGE_PATH):$(TAG) .

.PHONY: remediation-aggregator-image
remediation-aggregator-image:
	$(RUNTIME) build -f $(REMEDIATION_AGGREGATOR_DOCKERFILE_PATH) -t $(REMEDIATION_AGGREGATOR_IMAGE_PATH):$(TAG) .

.PHONY: build
build: manager resultscollector remediation-aggregator resultserver ## Build the compliance-operator binary

manager:
	$(GO) build -o $(TARGET) github.com/openshift/compliance-operator/cmd/manager

resultscollector:
	$(GO) build -o $(RESULTSCOLLECTOR_TARGET) github.com/openshift/compliance-operator/cmd/resultscollector

resultserver:
	$(GO) build -o $(RESULTSERVER_TARGET) github.com/openshift/compliance-operator/cmd/resultserver

remediation-aggregator:
	$(GO) build -o $(AGGREAGATOR_TARGET) github.com/openshift/compliance-operator/cmd/remediation-aggregator

.PHONY: operator-sdk
operator-sdk:
ifeq ("$(wildcard $(GOPATH)/bin/operator-sdk)","")
	wget -nv $(OPERATOR_SDK_URL) -O $(GOPATH)/bin/operator-sdk || (echo "wget returned $$? trying to fetch operator-sdk. please install operator-sdk and try again"; exit 1)
	chmod +x $(GOPATH)/bin/operator-sdk
endif

.PHONY: run
run: operator-sdk ## Run the compliance-operator locally
	WATCH_NAMESPACE=$(NAMESPACE) \
	KUBERNETES_CONFIG=$(KUBECONFIG) \
	OPERATOR_NAME=compliance-operator \
	$(GOPATH)/bin/operator-sdk up local --namespace $(NAMESPACE)

.PHONY: clean
clean: clean-modcache clean-cache clean-output ## Clean the golang environment

.PHONY: clean-output
clean-output:
	rm -rf $(TARGET_DIR)

.PHONY: clean-cache
clean-cache:
	$(GO) clean -cache -testcache $(PKGS)

.PHONY: clean-modcache
clean-modcache:
	$(GO) clean -modcache $(PKGS)

.PHONY: fmt
fmt:  ## Run the `go fmt` tool
	@$(GO) fmt $(PKGS)

.PHONY: simplify
simplify:
	@gofmt -s -l -w $(SRC)

.PHONY: verify
verify: vet mod-verify gosec ## Run code lint checks

.PHONY: vet
vet:
	@$(GO) vet $(PKGS)

.PHONY: mod-verify
mod-verify:
	@$(GO) mod verify

.PHONY: gosec
gosec:
	@$(GO) run github.com/securego/gosec/cmd/gosec -severity medium -confidence medium -quiet ./...

.PHONY: generate
generate: operator-sdk ## Run operator-sdk's code generation (k8s and openapi)
	$(GOPATH)/bin/operator-sdk generate k8s
	$(GOPATH)/bin/operator-sdk generate openapi

.PHONY: test-unit
test-unit: fmt ## Run the unit tests
	@$(GO) test $(TEST_OPTIONS) $(PKGS)

.PHONY: test-benchmark
test-benchmark: ## Run the benchmark tests -- Note that this can only be ran for one package. You can set $BENCHMARK_PKG for this. cpu.prof and mem.prof will be generated
	@$(GO) test -cpuprofile cpu.prof -memprofile mem.prof -bench . $(TEST_OPTIONS) $(BENCHMARK_PKG)
	@echo "The pprof files generated are: cpu.prof and mem.prof"

# This runs the end-to-end tests. If not running this on CI, it'll try to
# push the operator image to the cluster's registry. This behavior can be
# avoided with the E2E_SKIP_CONTAINER_PUSH environment variable.
.PHONY: e2e
ifeq ($(E2E_SKIP_CONTAINER_PUSH), false)
e2e: namespace operator-sdk image-to-cluster ## Run the end-to-end tests
else
e2e: namespace operator-sdk
endif
	@echo "WARNING: This will temporarily modify deploy/operator.yaml"
	@echo "Replacing workload references in deploy/operator.yaml"
	@sed -i 's%$(IMAGE_REPO)/$(RESULTSCOLLECTOR_IMAGE_NAME):latest%$(RESULTSCOLLECTOR_IMAGE_PATH)%' deploy/operator.yaml
	@sed -i 's%$(IMAGE_REPO)/$(RESULTSERVER_IMAGE_NAME):latest%$(RESULTSERVER_IMAGE_PATH)%' deploy/operator.yaml
	@sed -i 's%$(IMAGE_REPO)/$(REMEDIATION_AGGREGATOR_IMAGE_NAME):latest%$(REMEDIATION_AGGREGATOR_IMAGE_PATH)%' deploy/operator.yaml
	@echo "Running e2e tests"
	unset GOFLAGS && $(GOPATH)/bin/operator-sdk test local ./tests/e2e --image "$(OPERATOR_IMAGE_PATH)" --namespace "$(NAMESPACE)" --go-test-flags "$(E2E_GO_TEST_FLAGS)"
	@echo "Restoring image references in deploy/operator.yaml"
	@sed -i 's%$(RESULTSCOLLECTOR_IMAGE_PATH)%$(IMAGE_REPO)/$(RESULTSCOLLECTOR_IMAGE_NAME):latest%' deploy/operator.yaml
	@sed -i 's%$(RESULTSERVER_IMAGE_PATH)%$(IMAGE_REPO)/$(RESULTSERVER_IMAGE_NAME):latest%' deploy/operator.yaml
	@sed -i 's%$(REMEDIATION_AGGREGATOR_IMAGE_PATH)%$(IMAGE_REPO)/$(REMEDIATION_AGGREGATOR_IMAGE_NAME):latest%' deploy/operator.yaml

e2e-local: operator-sdk ## Run the end-to-end tests on a locally running operator (e.g. using make run)
	@echo "WARNING: This will temporarily modify deploy/operator.yaml"
	@echo "Replacing workload references in deploy/operator.yaml"
	@sed -i 's%$(IMAGE_REPO)/$(RESULTSCOLLECTOR_IMAGE_NAME):latest%$(RESULTSCOLLECTOR_IMAGE_PATH)%' deploy/operator.yaml
	@sed -i 's%$(IMAGE_REPO)/$(RESULTSERVER_IMAGE_NAME):latest%$(RESULTSERVER_IMAGE_PATH)%' deploy/operator.yaml
	unset GOFLAGS && $(GOPATH)/bin/operator-sdk test local ./tests/e2e --up-local --image "$(OPERATOR_IMAGE_PATH)" --namespace "$(NAMESPACE)" --go-test-flags "$(E2E_GO_TEST_FLAGS)"
	@echo "Restoring image references in deploy/operator.yaml"
	@sed -i 's%$(RESULTSCOLLECTOR_IMAGE_PATH)%$(IMAGE_REPO)/$(RESULTSCOLLECTOR_IMAGE_NAME):latest%' deploy/operator.yaml
	@sed -i 's%$(RESULTSERVER_IMAGE_PATH)%$(IMAGE_REPO)/$(RESULTSERVER_IMAGE_NAME):latest%' deploy/operator.yaml

# If IMAGE_FORMAT is not defined, it means that we're not running on CI, so we
# probably want to push the compliance-operator image to the cluster we're
# developing on. This target exposes temporarily the image registry, pushes the
# image, and remove the route in the end.
#
# The IMAGE_FORMAT variable comes from CI. It is of the format:
#     <image path in CI registry>:${component}
# Here define the `component` variable, so, when we overwrite the
# OPERATOR_IMAGE_PATH variable, it'll expand to the component we need.
# Note that the `component` names come from the `openshift/release` repo
# config.
.PHONY: image-to-cluster
ifdef IMAGE_FORMAT
image-to-cluster:
	@echo "IMAGE_FORMAT variable detected. We're in a CI enviornment."
	@echo "We're in a CI environment, skipping image-to-cluster target."
	$(eval component = $(APP_NAME))
	$(eval OPERATOR_IMAGE_PATH = $(IMAGE_FORMAT))
	$(eval component = compliance-resultscollector)
	$(eval RESULTSCOLLECTOR_IMAGE_PATH = $(IMAGE_FORMAT))
	$(eval component = compliance-resultserver)
	$(eval RESULTSERVER_IMAGE_PATH = $(IMAGE_FORMAT))
	$(eval component = compliance-remediation-aggregator)
	$(eval REMEDIATION_AGGREGATOR_IMAGE_PATH = $(IMAGE_FORMAT))
else
image-to-cluster: namespace openshift-user image
	@echo "IMAGE_FORMAT variable missing. We're in local enviornment."
	@echo "Temporarily exposing the default route to the image registry"
	@oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
	@echo "Pushing image $(OPERATOR_IMAGE_PATH):$(TAG) to the image registry"
	IMAGE_REGISTRY_HOST=$$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}'); \
		$(RUNTIME) login --tls-verify=false -u $(OPENSHIFT_USER) -p $(shell oc whoami -t) $${IMAGE_REGISTRY_HOST}; \
		$(RUNTIME) push --tls-verify=false $(OPERATOR_IMAGE_PATH):$(TAG) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(APP_NAME):$(TAG); \
		$(RUNTIME) push --tls-verify=false $(OPENSCAP_IMAGE_PATH):$(TAG) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(OPENSCAP_IMAGE_NAME):$(TAG); \
		$(RUNTIME) push --tls-verify=false $(RESULTSCOLLECTOR_IMAGE_PATH):$(TAG) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(RESULTSCOLLECTOR_IMAGE_NAME):$(TAG); \
		$(RUNTIME) push --tls-verify=false $(RESULTSERVER_IMAGE_PATH):$(TAG) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(RESULTSERVER_IMAGE_NAME):$(TAG); \
		$(RUNTIME) push --tls-verify=false $(REMEDIATION_AGGREGATOR_IMAGE_PATH):$(TAG) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(REMEDIATION_AGGREGATOR_IMAGE_NAME):$(TAG)
	@echo "Removing the route from the image registry"
	@oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":false}}' --type=merge
	$(eval OPERATOR_IMAGE_PATH = image-registry.openshift-image-registry.svc:5000/$(NAMESPACE)/$(APP_NAME):$(TAG))
	$(eval RESULTSCOLLECTOR_IMAGE_PATH = image-registry.openshift-image-registry.svc:5000/$(NAMESPACE)/$(RESULTSCOLLECTOR_IMAGE_NAME):$(TAG))
	$(eval RESULTSERVER_IMAGE_PATH = image-registry.openshift-image-registry.svc:5000/$(NAMESPACE)/$(RESULTSERVER_IMAGE_NAME):$(TAG))
	$(eval REMEDIATION_AGGREGATOR_IMAGE_PATH = image-registry.openshift-image-registry.svc:5000/$(NAMESPACE)/$(REMEDIATION_AGGREGATOR_IMAGE_NAME):$(TAG))
endif

.PHONY: namespace
namespace:
	@echo "Creating '$(NAMESPACE)' namespace/project"
	@oc create -f deploy/ns.yaml || true

.PHONY: openshift-user
openshift-user:
ifeq ($(shell oc whoami 2> /dev/null),kube:admin)
	$(eval OPENSHIFT_USER = kubeadmin)
else
	$(eval OPENSHIFT_USER = $(oc whoami))
endif

.PHONY: push
push: image
	# compliance-operator manager
	$(RUNTIME) tag $(OPERATOR_IMAGE_PATH) $(OPERATOR_IMAGE_PATH):$(TAG)
	$(RUNTIME) push $(OPERATOR_IMAGE_PATH):$(TAG)
	# resultscollector
	$(RUNTIME) tag $(RESULTSCOLLECTOR_IMAGE_PATH) $(RESULTSCOLLECTOR_IMAGE_PATH):$(TAG)
	$(RUNTIME) push $(RESULTSCOLLECTOR_IMAGE_PATH):$(TAG)
	# resultserver
	$(RUNTIME) tag $(RESULTSERVER_IMAGE_PATH) $(RESULTSERVER_IMAGE_PATH):$(TAG)
	$(RUNTIME) push $(RESULTSERVER_IMAGE_PATH):$(TAG)
	# remediation-aggregator
	$(RUNTIME) tag $(REMEDIATION_AGGREGATOR_IMAGE_PATH) $(REMEDIATION_AGGREGATOR_IMAGE_PATH):$(TAG)
	$(RUNTIME) push $(REMEDIATION_AGGREGATOR_IMAGE_PATH):$(TAG)

versionPath=$(shell GO111MODULE=on go list -f {{.Dir}} k8s.io/code-generator/cmd/client-gen)
codegeneratorRoot=$(versionPath:/cmd/client-gen=)
codegeneratorTarget:=./vendor/k8s.io/code-generator

# go mod doesn't mark scripts as executable, so we need to do that ourselves
.PHONY: code-generator
code-generator:
	@chmod +x $(codegeneratorTarget)/generate-groups.sh
	@chmod +x $(codegeneratorTarget)/generate-internal-groups.sh

.PHONY: gen-mcfg-client
gen-mcfg-client: code-generator
	$(codegeneratorTarget)/generate-groups.sh client \
		github.com/openshift/compliance-operator/pkg/generated \
		github.com/openshift/compliance-operator/pkg/apis \
		"machineconfiguration:v1" \
		--go-header-file=./custom-boilerplate.go.txt
	cp -r $(GOPATH)/src/github.com/openshift/compliance-operator/pkg/generated pkg/

.PHONY: publish
publish:
	$(COURIER_CMD) push "$(COURIER_OPERATOR_DIR)" "$(COURIER_QUAY_NAMESPACE)" "$(COURIER_PACKAGE_NAME)" "$(COURIER_PACKAGE_VERSION)" "basic $(COURIER_QUAY_TOKEN)"
