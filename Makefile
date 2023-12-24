# Project Setup
PROJECT_NAME := issue-59
PROJECT_REPO := github.com/haarchri/$(PROJECT_NAME)
PLATFORMS ?= linux_amd64
-include build/makelib/common.mk

# ====================================================================================
# Setup Kubernetes tools

UP_VERSION = v0.20.0
UP_CHANNEL = stable
UPTEST_VERSION = v0.8.0
UPTEST_CLAIMS ?= examples/claim.yaml

-include build/makelib/k8s_tools.mk
# ====================================================================================
# Setup XPKG
XPKG_DIR = $(shell pwd)
XPKG_IGNORE = .github/workflows/*.yaml,.github/workflows/*.yml,examples/*.yaml,.work/uptest-datasource.yaml,examples/*.yaml,test/providerconfig/*.yaml
XPKG_REG_ORGS ?= xpkg.upbound.io/haarchri
XPKG_REG_ORGS_NO_PROMOTE ?= xpkg.upbound.io/haarchri
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

CROSSPLANE_NAMESPACE = upbound-system
CROSSPLANE_ARGS = "--enable-usages"
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

# ====================================================================================
# Targets

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
# The first time `make` is run, the includes of build/*.mk files will
# all fail, and this target will be run. The next time, the default as defined
# by the includes will be run instead.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

# Update the submodules, such as the common build scripts.
submodules:
	@git submodule sync
	@git submodule update --init --recursive

# We must ensure up is installed in tool cache prior to build as including the k8s_tools machinery prior to the xpkg
# machinery sets UP to point to tool cache.
build.init: $(UP)

# ====================================================================================
# End to End Testing

# This target requires the following environment variables to be set:
# - UPTEST_CLOUD_CREDENTIALS, cloud credentials for the provider being tested, e.g. export UPTEST_CLOUD_CREDENTIALS=$(cat ~/.aws/credentials)
# - To ensure the proper functioning of the end-to-end test resource pre-deletion hook, it is crucial to arrange your resources appropriately.
#   You can check the basic implementation here: https://github.com/upbound/uptest/blob/main/internal/templates/01-delete.yaml.tmpl.
# - UPTEST_DATASOURCE_PATH (optional), see https://github.com/upbound/uptest#injecting-dynamic-values-and-datasource
uptest: $(UPTEST) $(KUBECTL) $(KUTTL)
	@$(INFO) running automated tests
	@if [ "${UPTEST_SKIP_DELETE}" = "true" ]; then \
		echo "Running uptest and we will not remove resource..."; \
		KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) $(UPTEST) e2e $(UPTEST_CLAIMS) --data-source="${UPTEST_DATASOURCE_PATH}" --setup-script=test/setup.sh --default-timeout=2400 --skip-delete || $(FAIL); \
	else \
		echo "Running uptest and we will remove resources..."; \
		KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) $(UPTEST) e2e $(UPTEST_CLAIMS) --data-source="${UPTEST_DATASOURCE_PATH}" --setup-script=test/setup.sh --default-timeout=2400 || $(FAIL); \
	fi
	@$(OK) running automated tests

# This target requires the following environment variables to be set:
# - UPTEST_CLOUD_CREDENTIALS, cloud credentials for the provider being tested, e.g. export UPTEST_CLOUD_CREDENTIALS=$(cat ~/.aws/credentials)
e2e: build controlplane.up local.xpkg.deploy.configuration.$(PROJECT_NAME) uptest

.PHONY: uptest e2e
