# Workstation image build.
#
#   make image   build a bootable image from ansible/group_vars/all.yml
#   make apply   converge THIS machine to the same config, without reimaging
#
# `make help` lists everything.

SHELL := /bin/bash
# -e and pipefail, because .ONESHELL below makes each recipe a single shell and
# make then reads only its LAST command's status. Without these, any command
# that fails mid-recipe is invisible: `make image` reported success after packer
# errored, and lint-packer ignored `packer fmt -check` entirely because a passing
# `packer validate` followed it. Two recipes need an explicit `|| true` to stay
# correct under this -- both are marked where they are.
.SHELLFLAGS := -e -o pipefail -c
.DEFAULT_GOAL := help
.ONESHELL:

# 2026.08.27-a1b2c3d -- date for humans, sha so a build maps back to a commit.
GIT_SHA     := $(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
GIT_DIRTY   := $(shell test -n "$$(git status --porcelain 2>/dev/null)" && echo '-dirty' || echo '')
VERSION     ?= $(shell date -u +%Y.%m.%d)-$(GIT_SHA)$(GIT_DIRTY)

BUILD_DIR   ?= build
IMAGE_NAME  ?= workstation
# The directory a build's artifacts land in -- not an artifact itself.
# See CONTEXT.md: an artifact is one published file.
ARTIFACT_DIR := $(BUILD_DIR)/$(IMAGE_NAME)-$(VERSION)
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

# The one converge command line. `make apply`, `make apply-check` and both runs
# in .github/workflows/apply.yml build on it, so CI converges exactly the way a
# workstation does -- before, the same flags were written out four times and
# had already drifted (apply-check never passed workstation_image_version).
# Packer's ansible provisioner runs the same playbook for the image phase but
# invokes ansible-playbook itself; its flags live in packer/workstation.pkr.hcl.
#
# ASK_BECOME_PASS is cleared by CI, whose runners have passwordless sudo and no
# terminal to prompt on: `make apply ASK_BECOME_PASS=`.
ASK_BECOME_PASS ?= --ask-become-pass
CONVERGE = ansible-playbook $(PLAYBOOK) \
  -i localhost, -c local \
  -e workstation_phase=live \
  -e workstation_image_version=$(VERSION) \
  $(BECOME_EXE) $(ASK_BECOME_PASS)

.PHONY: help
help: ## Show this help
	@echo "Workstation image build"
	@echo
	@# `|| true`: under .SHELLFLAGS pipefail, a grep that matches nothing would
	@# abort `make help` itself rather than just printing a shorter list.
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' \
	  || true
	@echo
	@echo "  Version for this build: $(VERSION)"

# --- Dependencies -------------------------------------------------------------

.PHONY: doctor
doctor: ## Check this machine still matches what the repo assumes
	@scripts/doctor.sh

.PHONY: deps
deps: ## Install Ansible collections
	ansible-galaxy collection install -r ansible/requirements.yml

.PHONY: check-tools
check-tools:
	@# The build's prerequisites -- tools and an accessible /dev/kvm -- checked
	@# by doctor, so the two cannot drift apart again (they had: different tool
	@# lists, two copies of the KVM diagnosis). Fails before the ISO download
	@# rather than as Packer's generic "Qemu failed to start" an hour later.
	@scripts/doctor.sh --build

# --- Build --------------------------------------------------------------------

.PHONY: init
init: ## Install Packer plugins
	packer init packer/

.PHONY: image
image: check-tools init deps ## Build the image (qcow2 + raw)
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
	@# No `|| exit` needed after packer: .SHELLFLAGS carries -e, so a failed
	@# build stops the recipe here instead of printing "Built ..." below it.
	@echo
	@echo "Built $(ARTIFACT_DIR)/$(IMAGE_NAME)-$(VERSION).{qcow2,raw}.zst"
	@ls -lh $(ARTIFACT_DIR)/ 2>/dev/null || true

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
	@test -f "$(ARTIFACT_DIR)/$(IMAGE_NAME)-$(VERSION).qcow2" \
	  || { echo "No image for $(VERSION). Run 'make image' first."; exit 1; }
	terraform -chdir=terraform/testlab init -input=false
	terraform -chdir=terraform/testlab apply -auto-approve \
	  -var "image_path=$(CURDIR)/$(ARTIFACT_DIR)/$(IMAGE_NAME)-$(VERSION).qcow2" \
	  -var "image_version=$(VERSION)"
	@echo
	@echo "VM booted and took a DHCP lease:"
	@terraform -chdir=terraform/testlab output ip_address
	@echo "Watch firstboot:  $$(terraform -chdir=terraform/testlab output -raw console_command)"
	@echo "Tear down:        make test-down"

.PHONY: test-down
test-down: ## Destroy the test VM
	terraform -chdir=terraform/testlab destroy -auto-approve \
	  -var "image_path=/dev/null" -var "image_version=$(VERSION)"

# --- Distribute ---------------------------------------------------------------

.PHONY: publish
publish: ## Upload the built image and move the channel
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
	$(CONVERGE) $(ARGS)

.PHONY: apply-check
apply-check: deps ## Show what `make apply` would change, without changing it
	$(CONVERGE) --check --diff $(ARGS)

.PHONY: verify
verify: ## Check THIS machine against what it was last converged to (after make apply)
	@# The shared goss suite: the same one apply.yml runs on every pull request
	@# and the image build runs inside image.yaml. It reads the declared set the
	@# last converge recorded, so run `make apply` first after editing group_vars.
	@# sudo because some checks read root-only state (debsig keyrings, dconf).
	sudo tests/goss/run-goss.sh tests/goss/shared.yaml

# --- Documentation -----------------------------------------------------------

.PHONY: verify-repos
verify-repos: ## Check every third-party apt repo declared in group_vars
	python3 scripts/verify-repos.py

.PHONY: docs
docs: ## Render the built image's contents as HTML and show where it is
	@test -f "$(ARTIFACT_DIR)/workstation-manifest.json" \
	  || { echo "No manifest for $(VERSION). Run 'make image' first."; exit 1; }
	python3 scripts/render-docs.py \
	  --manifest "$(ARTIFACT_DIR)/workstation-manifest.json" \
	  --declared "$(ARTIFACT_DIR)/workstation-declared.json" \
	  -o "$(ARTIFACT_DIR)/docs.html"
	@echo "Open: $(ARTIFACT_DIR)/docs.html"

.PHONY: docs-config
docs-config: ## Regenerate the committed reference docs from source
	@# docsible writes a README.md into each role directory, which is where
	@# someone browsing that role on GitHub will look for it. It warns about
	@# absent tests/test.yml on every role; that is expected, not a problem.
	@# A failure must fail the target: lint-docs discards this output and only
	@# diffs the result, so a docsible that failed left every README untouched,
	@# the diff empty, and lint-docs green over docs nothing had regenerated.
	@failed=""
	for role in ansible/roles/*/; do
	  docsible --role "$$role" --comments --no-docsible --no-backup >/dev/null 2>&1 \
	    || failed="$$failed $$role"
	done
	if [ -n "$$failed" ]; then
	  echo "docsible failed for:$$failed" >&2
	  exit 1
	fi
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

.PHONY: lint-commits
lint-commits: ## Check commit messages. Usage: make lint-commits [RANGE=A..B]
	@# Deliberately NOT part of `lint`: that target runs before a commit exists
	@# (the config-change skill calls it at verify time), where checking earlier
	@# commits is pure noise. Defaults to HEAD alone because every commit made
	@# before this convention was adopted predates it -- history is grandfathered,
	@# not rewritten. See CONTRIBUTING.md.
	python3 scripts/lint-commit-msg.py $(if $(RANGE),--range $(RANGE),)

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
	@# Both phases: each gates different roles, so one alone leaves the other's
	@# tasks unparsed.
	for phase in image live; do
	  echo "--- phase=$$phase"
	  ansible-playbook $(PLAYBOOK) -i localhost, -c local \
	    -e "workstation_phase=$$phase" --syntax-check
	done

.PHONY: lint-packer
lint-packer:
	@# A full validate, not -syntax-only: that skips evaluating locals, so a
	@# broken expression -- the versions.env lookup, say -- passes lint and
	@# fails at build time. Like lint-terraform's validate, it needs the
	@# plugins and therefore network on a cold run.
	packer fmt -check -diff packer/
	packer init packer/ >/dev/null
	packer validate packer/

.PHONY: lint-terraform
# fmt alone only checks layout. CI has always run `validate` as well and local
# lint did not, so `make lint` reported clean while the testlab module could not
# even initialise: it declared a variable named "version", which Terraform
# reserves, and its provider constraint "~> 0.8" let the breaking 0.9 schema in.
# Both were invisible to fmt, so `make test` had never been able to work.
#
# Validating costs a provider download on a cold run and needs network, which is
# presumably why it was left out. That is a poor trade against a linter that
# passes on a module which cannot start.
lint-terraform:
	terraform fmt -check -recursive terraform/
	@for dir in terraform/*/; do \
	  echo "--- $$dir"; \
	  terraform -chdir="$$dir" init -backend=false -input=false >/dev/null || exit 1; \
	  terraform -chdir="$$dir" validate || exit 1; \
	done

.PHONY: lint-shell
lint-shell:
	@# Collected with find rather than globs: an unmatched glob is passed
	# through literally and shellcheck then fails on a path that does not
	# exist, which reads like a broken lint rather than a missing directory.
	@# `|| true`: find exits non-zero when .claude is missing, and under
	@# .SHELLFLAGS pipefail that would abort here -- reintroducing exactly the
	@# "lint-shell on trees without a .claude directory" bug already fixed once.
	@# Skills installed with `npx skills add` are listed in skills-lock.json and
	@# skipped: they are vendored, the way ansible/.collections is for
	@# ansible-lint, and `npx skills update` would overwrite any fix made here.
	vendored=$$(python3 -c 'import json; print("|".join(json.load(open("skills-lock.json"))["skills"]))' 2>/dev/null) || true
	sh_files=$$(find scripts tests .claude -name '*.sh' 2>/dev/null | sort \
	  | grep -vE "^\.claude/skills/($${vendored:-^})/") || true
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
