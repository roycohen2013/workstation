# Workstation image build.
#
#   make image   build a bootable image from ansible/group_vars/all.yml
#   make apply   converge THIS machine to the same config, without reimaging
#
# `make help` lists everything.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.ONESHELL:

# 2026.08.27-a1b2c3d -- date for humans, sha so a build maps back to a commit.
GIT_SHA     := $(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
GIT_DIRTY   := $(shell test -n "$$(git status --porcelain 2>/dev/null)" && echo '-dirty' || echo '')
VERSION     ?= $(shell date -u +%Y.%m.%d)-$(GIT_SHA)$(GIT_DIRTY)

BUILD_DIR   ?= build
IMAGE_NAME  ?= workstation
ARTIFACT    := $(BUILD_DIR)/$(IMAGE_NAME)-$(VERSION)
PLAYBOOK    := ansible/site.yml

export ANSIBLE_CONFIG := $(CURDIR)/ansible.cfg

# Ubuntu 26.04 points /usr/bin/sudo at sudo-rs, the Rust reimplementation.
# It treats a caller-supplied -p prompt as untrusted text: instead of showing
# it, it echoes it inside a "[sudo: ...]" annotation and then prompts with its
# own generic "Password:". Ansible's become plugin waits for the exact
# key-tagged prompt it asked for, never sees it, and every run dies with
# "Timed out waiting for become success or become password prompt" -- with a
# correct password, and with sudo sitting there ready to accept it.
#
# Confirmed by running the two binaries side by side with the same -p string:
#   sudo-rs      [sudo: [sudo via ansible, key=X] password:] Password:
#   classic sudo [sudo via ansible, key=X] password:
# and then by pointing become_exe at the classic binary and feeding Ansible a
# deliberately wrong password: it changes from timing out without ever
# submitting anything to submitting it and getting "Sorry, try again" back,
# which is prompt detection working.
#
# Ubuntu keeps the classic implementation installed alongside as sudo.ws. On
# any machine without it this expands to nothing and the default sudo is used,
# so this stays a no-op everywhere the problem does not exist.
SUDO_WS    := $(shell command -v sudo.ws 2>/dev/null)
BECOME_EXE := $(if $(SUDO_WS),-e ansible_become_exe=$(SUDO_WS),)

.PHONY: help
help: ## Show this help
	@echo "Workstation image build"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  Version for this build: $(VERSION)"

# --- Dependencies -------------------------------------------------------------

.PHONY: deps
deps: ## Install Ansible collections
	ansible-galaxy collection install -r ansible/requirements.yml

.PHONY: check-tools
check-tools:
	@missing=""
	for t in packer qemu-img ansible-playbook; do
	  command -v $$t >/dev/null || missing="$$missing $$t"
	done
	if [ -n "$$missing" ]; then
	  echo "Missing required tools:$$missing"
	  echo "  Ubuntu: sudo apt install qemu-utils qemu-system-x86 ovmf ansible"
	  echo "  Packer: https://developer.hashicorp.com/packer/install"
	  exit 1
	fi
	if [ ! -e /dev/kvm ]; then
	  echo "/dev/kvm is missing -- the build needs hardware virtualisation."
	  echo "Enable VT-x/AMD-V in firmware. On WSL2, also enable nested"
	  echo "virtualisation (nestedVirtualization=true in .wslconfig on Windows)."
	  exit 1
	fi
	if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
	  echo "/dev/kvm exists but this user cannot access it (device group: $$(stat -c %G /dev/kvm 2>/dev/null))."
	  echo "This is the single most common first-build failure: qemu starts,"
	  echo "gets 'Permission denied' opening /dev/kvm, and Packer only reports"
	  echo "the generic 'Qemu failed to start' -- after downloading the ISO and"
	  echo "waiting through the boot timeout first."
	  echo
	  echo "Fix:"
	  echo "    sudo usermod -aG kvm $$USER"
	  echo "    # then log out and back in (or reboot) -- a new group only takes"
	  echo "    # effect in a new login session, not the current shell"
	  echo
	  echo "Confirm before re-running make image:"
	  echo "    groups                 # should list kvm"
	  echo "    qemu-system-x86_64 -enable-kvm -m 256 -nographic -serial none"
	  exit 1
	fi

# --- Build --------------------------------------------------------------------

.PHONY: init
init: ## Install Packer plugins
	packer init packer/

.PHONY: image
image: check-tools init deps ## Build the golden image (qcow2 + raw)
	# -force: the qemu builder refuses to run if its output directory already
	# exists, and a build that dies partway (crash, Ctrl-C, a machine reboot
	# mid-compression) always leaves one behind. Without this, every retry
	# after any interruption fails immediately with "must not exist" instead
	# of actually retrying -- confirmed by reproducing that exact error and
	# confirming -force is what clears it, packer's own documented mechanism
	# for this, rather than this Makefile reimplementing the cleanup itself.
	packer build \
	  -force \
	  -var "version=$(VERSION)" \
	  -var "image_name=$(IMAGE_NAME)" \
	  -var "output_dir=$(BUILD_DIR)" \
	  $(ARGS) \
	  packer/
	@echo
	@echo "Built $(ARTIFACT).{qcow2,raw}.zst"
	@ls -lh $(ARTIFACT)/ 2>/dev/null || true

.PHONY: image-debug
image-debug: check-tools init deps ## Build with the installer visible, for debugging
	PACKER_LOG=1 packer build -var "version=$(VERSION)" -var "headless=false" \
	  -on-error=ask packer/

.PHONY: iso
iso: ## Build the unattended installer ISO
	VERSION=$(VERSION) scripts/build-iso.sh

# --- Verify -------------------------------------------------------------------

.PHONY: test
test: ## Boot the built image in libvirt and check it comes up
	@test -f "$(ARTIFACT)/$(IMAGE_NAME)-$(VERSION).qcow2" \
	  || { echo "No image for $(VERSION). Run 'make image' first."; exit 1; }
	terraform -chdir=terraform/testlab init -input=false
	terraform -chdir=terraform/testlab apply -auto-approve \
	  -var "image_path=$(CURDIR)/$(ARTIFACT)/$(IMAGE_NAME)-$(VERSION).qcow2" \
	  -var "version=$(VERSION)"
	@echo
	@echo "VM booted and took a DHCP lease:"
	@terraform -chdir=terraform/testlab output ip_address
	@echo "Watch firstboot:  $$(terraform -chdir=terraform/testlab output -raw console_command)"
	@echo "Tear down:        make test-down"

.PHONY: test-down
test-down: ## Destroy the test VM
	terraform -chdir=terraform/testlab destroy -auto-approve \
	  -var "image_path=/dev/null" -var "version=$(VERSION)"

# --- Distribute ---------------------------------------------------------------

.PHONY: publish
publish: ## Upload the built image and move the channel pointer
	VERSION=$(VERSION) scripts/publish-image.sh

.PHONY: fetch
fetch: ## Download the latest published image
	scripts/fetch-image.sh

.PHONY: flash
flash: ## Write an image to a disk. Usage: make flash DEV=/dev/sdX
	@test -n "$(DEV)" || { echo "Usage: make flash DEV=/dev/sdX"; exit 1; }
	scripts/flash.sh --device $(DEV)

# --- Apply to a running machine ----------------------------------------------

.PHONY: apply
apply: deps ## Converge THIS machine to the config (no reimage)
	ansible-playbook $(PLAYBOOK) \
	  -i localhost, -c local \
	  -e workstation_phase=live \
	  -e workstation_image_version=$(VERSION) \
	  $(BECOME_EXE) \
	  --ask-become-pass $(ARGS)

.PHONY: apply-check
apply-check: deps ## Show what `make apply` would change, without changing it
	ansible-playbook $(PLAYBOOK) \
	  -i localhost, -c local \
	  -e workstation_phase=live \
	  $(BECOME_EXE) \
	  --check --diff --ask-become-pass $(ARGS)

# --- Documentation -----------------------------------------------------------

.PHONY: verify-repos
verify-repos: ## Check every third-party apt repo declared in group_vars
	python3 scripts/verify-repos.py

.PHONY: docs
docs: ## Render the built image's contents as HTML and show where it is
	@test -f "$(ARTIFACT)/workstation-manifest.json" \
	  || { echo "No manifest for $(VERSION). Run 'make image' first."; exit 1; }
	python3 scripts/render-docs.py \
	  --manifest "$(ARTIFACT)/workstation-manifest.json" \
	  --declared "$(ARTIFACT)/workstation-declared.json" \
	  -o "$(ARTIFACT)/docs.html"
	@echo "Open: $(ARTIFACT)/docs.html"

.PHONY: docs-config
docs-config: ## Regenerate the committed reference docs from source
	@# docsible writes a README.md into each role directory, which is where
	@# someone browsing that role on GitHub will look for it. It warns about
	@# absent tests/test.yml on every role; that is expected, not a problem.
	@for role in ansible/roles/*/; do \
	  docsible --role "$$role" --comments --no-docsible --no-backup >/dev/null 2>&1 \
	    || echo "  docsible failed for $$role"; \
	done
	python3 scripts/gen-config-docs.py

.PHONY: docs-diff
docs-diff: ## Compare two builds. Usage: make docs-diff FROM=<version> TO=<version>
	@test -n "$(FROM)" -a -n "$(TO)" \
	  || { echo "Usage: make docs-diff FROM=<version> TO=<version>"; exit 1; }
	python3 scripts/render-docs.py \
	  --diff "$(BUILD_DIR)/$(IMAGE_NAME)-$(FROM)/workstation-manifest.json" \
	         "$(BUILD_DIR)/$(IMAGE_NAME)-$(TO)/workstation-manifest.json" \
	  -o "$(BUILD_DIR)/diff-$(FROM)-to-$(TO).html"
	@echo "Open: $(BUILD_DIR)/diff-$(FROM)-to-$(TO).html"

# --- Lint ---------------------------------------------------------------------

.PHONY: lint
lint: lint-yaml lint-ansible lint-packer lint-terraform lint-shell lint-docs ## Run every linter

.PHONY: lint-docs
lint-docs: ## Fail if the committed docs are stale relative to source
	@# Regenerates everything docs-config produces -- the role READMEs included,
	@# since those are committed too -- and fails if anything moved. Without
	@# this the docs are decorative: nothing would ever catch them drifting.
	@$(MAKE) --no-print-directory docs-config >/dev/null
	@git diff --exit-code --stat docs/ ansible/roles/*/README.md \
	  || { echo "Docs are stale -- run 'make docs-config' and commit the result"; exit 1; }

.PHONY: lint-yaml
lint-yaml:
	yamllint -c .yamllint ansible/ tests/ iso/ packer/http/ .github/

.PHONY: lint-ansible
lint-ansible:
	ansible-lint ansible/
	ansible-playbook $(PLAYBOOK) -i localhost, -c local \
	  -e workstation_phase=image --syntax-check

.PHONY: lint-packer
lint-packer:
	packer fmt -check -diff packer/
	packer validate -syntax-only packer/

.PHONY: lint-terraform
lint-terraform:
	terraform fmt -check -recursive terraform/

.PHONY: lint-shell
lint-shell:
	@# Collected with find rather than globs: an unmatched glob is passed
	# through literally and shellcheck then fails on a path that does not
	# exist, which reads like a broken lint rather than a missing directory.
	sh_files=$$(find scripts tests .claude -name '*.sh' 2>/dev/null | sort)
	if [ -z "$$sh_files" ]; then echo "lint-shell: no shell scripts found"; exit 0; fi
	shellcheck $$sh_files

.PHONY: fmt
fmt: ## Reformat Packer and Terraform files in place
	packer fmt packer/
	terraform fmt -recursive terraform/

# --- Housekeeping -------------------------------------------------------------

.PHONY: clean
clean: ## Remove build output (keeps the downloaded ISO cache)
	rm -rf $(BUILD_DIR)/workstation-* $(BUILD_DIR)/downloads

.PHONY: clean-all
clean-all: ## Remove everything, including the cached installer ISO
	rm -rf $(BUILD_DIR)

.PHONY: version
version: ## Print the version this build would use
	@echo $(VERSION)
