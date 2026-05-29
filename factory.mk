# =============================================================================
# factory.mk — AutoCodeEngine
#
# USAGE A — git submodule (recommended, zero repo pollution):
#   git submodule add https://github.com/trushilpatel/AutoCodeEngine tools/autocode
#   bash tools/autocode/install.sh
#   # Add to bottom of your existing Makefile (or create one):
#   include tools/autocode/factory.mk
#
# USAGE B — standalone (no existing Makefile):
#   cp tools/autocode/factory.mk Makefile
#   # All engine paths auto-resolve relative to this file's location.
#
# CONFIGURATION:
#   cp tools/autocode/.factory.env.example .factory.env
#   # Edit .factory.env — it is gitignored. All variables can also be
#   # overridden on the command line:  make run FEATURE=login MAX_AGENT_CALLS=30
# =============================================================================

# ── Auto-detect where factory.mk lives ────────────────────────────────────────
# Works whether this file is:
#   - Included as  include tools/autocode/factory.mk
#   - Symlinked / copied to repo root as Makefile
#   - Run directly with  make -f tools/autocode/factory.mk
#
# During `include`, $(lastword $(MAKEFILE_LIST)) resolves to THIS file's path.
# We capture it before .factory.env is loaded so it can't be overridden.
_FACTORY_MK   := $(abspath $(lastword $(MAKEFILE_LIST)))
_FACTORY_DIR  := $(patsubst %/,%,$(dir $(_FACTORY_MK)))

# ── Load project config (gitignored, never committed) ─────────────────────────
-include .factory.env

# ── Default variable values ────────────────────────────────────────────────────
# Two-tier KB:
#   KB_DIR        — project KB, lives at repo root, committed to your project
#   ENGINE_KB_DIR — engine KB, lives inside AutoCodeEngine, committed here
#                   (generalizable patterns shared across all projects)
#
# Engine paths (scripts/templates) auto-resolve to inside the submodule.
# Project paths (features/kb) default to repo root so they're version-controlled.
MODEL_HAIKU     ?= claude-haiku-4-5
MODEL_SONNET    ?= claude-sonnet-4-5
MODEL_OPUS      ?= claude-opus-4-6
MAX_LOOP_BACKS  ?= 3
MAX_AGENT_CALLS ?= 50
BASE_URL        ?= http://localhost:3000
TEST_CMD        ?=
SKIP_GATES      ?=
FEATURES_DIR    ?= features
KB_DIR          ?= kb
ENGINE_KB_DIR   ?= $(_FACTORY_DIR)/kb
AGENTS_DIR      ?= .claude/agents
SCRIPTS_DIR     ?= $(_FACTORY_DIR)/scripts
TEMPLATES_DIR   ?= $(_FACTORY_DIR)/templates
PERF_P95_MS     ?= 300
PERF_P99_MS     ?= 1000
PERF_ERROR_RATE ?= 0.01
PERF_BUNDLE_KB  ?= 20

# Export everything so sub-scripts see all variables
export MODEL_HAIKU MODEL_SONNET MODEL_OPUS
export MAX_LOOP_BACKS MAX_AGENT_CALLS
export BASE_URL TEST_CMD SKIP_GATES
export FEATURES_DIR KB_DIR ENGINE_KB_DIR AGENTS_DIR SCRIPTS_DIR TEMPLATES_DIR
export PERF_P95_MS PERF_P99_MS PERF_ERROR_RATE PERF_BUNDLE_KB

# ── Colours ────────────────────────────────────────────────────────────────────
CYAN  := \033[0;36m
RESET := \033[0m

# =============================================================================
# Targets
# =============================================================================

.DEFAULT_GOAL := help

.PHONY: help install new run resume status list budget steward steward-deep check clean

## ── Setup ──────────────────────────────────────────────────────────────────────

help: ## Show all available commands (default)
	@echo ""
	@echo "  AutoCodeEngine"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*##"}; \
	       /^## / { printf "\n  %s\n", substr($$0,4) } \
	       /^[a-z]/ { printf "  $(CYAN)%-18s$(RESET) %s\n", $$1, $$2 }'
	@echo ""
	@echo "  Paths:"
	@echo "    FEATURES_DIR=$(FEATURES_DIR)   KB_DIR=$(KB_DIR)"
	@echo "    ENGINE_KB_DIR=$(ENGINE_KB_DIR)"
	@echo "    AGENTS_DIR=$(AGENTS_DIR)"
	@echo ""
	@echo "  Models & limits:"
	@echo "    MODEL_HAIKU=$(MODEL_HAIKU)  MODEL_SONNET=$(MODEL_SONNET)  MODEL_OPUS=$(MODEL_OPUS)"
	@echo "    MAX_LOOP_BACKS=$(MAX_LOOP_BACKS)   MAX_AGENT_CALLS=$(MAX_AGENT_CALLS)"
	@echo "    BASE_URL=$(BASE_URL)   SKIP_GATES=$(SKIP_GATES)"
	@echo ""

install: ## First-time setup: checks prereqs, installs agents and hooks
	@bash $(_FACTORY_DIR)/install.sh

check: ## Verify prerequisites without installing
	@bash $(_FACTORY_DIR)/install.sh --check-only

## ── Daily workflow ─────────────────────────────────────────────────────────────

new: ## Create a feature PRD from template.  Usage: make new FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make new FEATURE=<slug>"; exit 1)
	@mkdir -p $(FEATURES_DIR)/$(FEATURE)
	@if [ -f "$(FEATURES_DIR)/$(FEATURE)/PRD.md" ]; then \
	  echo "⚠️  $(FEATURES_DIR)/$(FEATURE)/PRD.md already exists — not overwriting."; \
	else \
	  cp $(TEMPLATES_DIR)/PRD.md $(FEATURES_DIR)/$(FEATURE)/PRD.md; \
	  echo "✅ PRD created: $(FEATURES_DIR)/$(FEATURE)/PRD.md"; \
	  echo "   Fill in every section, then: make run FEATURE=$(FEATURE)"; \
	fi

run: ## Start the feature loop.  Usage: make run FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make run FEATURE=<slug>"; exit 1)
	@test -f "$(FEATURES_DIR)/$(FEATURE)/PRD.md" || \
	  (echo "PRD not found. Run: make new FEATURE=$(FEATURE)"; exit 1)
	@bash $(SCRIPTS_DIR)/run-feature.sh $(FEATURES_DIR)/$(FEATURE)/PRD.md

resume: ## Resume an interrupted feature.  Usage: make resume FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make resume FEATURE=<slug>"; exit 1)
	@test -f "$(FEATURES_DIR)/$(FEATURE)/state.yaml" || \
	  (echo "No state.yaml found — start with: make run FEATURE=$(FEATURE)"; exit 1)
	@bash $(SCRIPTS_DIR)/run-feature.sh $(FEATURES_DIR)/$(FEATURE)/state.yaml --resume

## ── Visibility ─────────────────────────────────────────────────────────────────

status: ## Show gate dashboard for a feature.  Usage: make status FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make status FEATURE=<slug>"; exit 1)
	@bash $(SCRIPTS_DIR)/show-status.sh $(FEATURES_DIR)/$(FEATURE)/state.yaml

list: ## List all features and their current status
	@bash $(SCRIPTS_DIR)/show-status.sh --list $(FEATURES_DIR)

budget: ## Show agent call count for a feature.  Usage: make budget FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make budget FEATURE=<slug>"; exit 1)
	@bash $(SCRIPTS_DIR)/show-budget.sh $(FEATURES_DIR)/$(FEATURE) $(MAX_AGENT_CALLS)

## ── Knowledge base ─────────────────────────────────────────────────────────────

steward: ## Run Steward after merge (classifies learnings to project KB + engine KB proposals).  Usage: make steward FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make steward FEATURE=<slug>"; exit 1)
	@bash $(SCRIPTS_DIR)/run-steward.sh $(FEATURE)

steward-deep: ## Run full Steward hygiene pass on both KBs (weekly)
	@bash $(SCRIPTS_DIR)/run-steward.sh --full-pass

## ── Housekeeping ───────────────────────────────────────────────────────────────

clean: ## Remove state file for a feature (keeps PRD and outputs).  Usage: make clean FEATURE=my-feature
	@test -n "$(FEATURE)" || (echo "Usage: make clean FEATURE=<slug>"; exit 1)
	@read -p "Remove state.yaml and .agent-calls for $(FEATURE)? [y/N] " confirm; \
	  [ "$$confirm" = "y" ] || exit 0; \
	  rm -f $(FEATURES_DIR)/$(FEATURE)/state.yaml; \
	  rm -f $(FEATURES_DIR)/$(FEATURE)/state.md; \
	  rm -f $(FEATURES_DIR)/$(FEATURE)/.agent-calls; \
	  echo "Cleaned. Re-run with: make run FEATURE=$(FEATURE)"
