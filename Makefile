.PHONY: dev-link dev-unlink dsh-link dsh-unlink dsh-install dsh-remove validate test site-dev site-build lint format lint-fix

PLUGIN_NAME := fullstack-dev-skills
VERSION := $(shell python -c "import json; print(json.load(open('version.json'))['version'])")
CACHE_BASE := $(HOME)/.claude/plugins/cache/$(PLUGIN_NAME)/$(PLUGIN_NAME)
CACHE_DIR := $(CACHE_BASE)/$(VERSION)
DSH_HOME ?= $(HOME)/.dsh
DSH_SKILLS := $(DSH_HOME)/skills
DSH_BUILD := $(CURDIR)/dist/dsh/skills

dev-link:
	@if [ -L "$(CACHE_DIR)" ]; then \
		echo "Error: $(CACHE_DIR) is already a symlink."; \
		exit 1; \
	fi
	@if [ -d "$(CACHE_DIR).bak" ]; then \
		echo "Error: Backup already exists at $(CACHE_DIR).bak"; \
		echo "Run 'make dev-unlink' first to restore it."; \
		exit 1; \
	fi
	@if [ ! -d "$(CACHE_DIR)" ]; then \
		echo "Error: Cache directory not found at $(CACHE_DIR)"; \
		echo "Is the plugin installed? Check: cat ~/.claude/plugins/installed_plugins.json"; \
		exit 1; \
	fi
	mv "$(CACHE_DIR)" "$(CACHE_DIR).bak"
	ln -s "$(CURDIR)" "$(CACHE_DIR)"
	@echo ""
	@echo "Linked: $(CACHE_DIR) -> $(CURDIR)"
	@echo "Restart Claude Code to load changes from your working copy."

dev-unlink:
	@if [ ! -L "$(CACHE_DIR)" ]; then \
		echo "Error: $(CACHE_DIR) is not a symlink. Nothing to unlink."; \
		exit 1; \
	fi
	@if [ ! -d "$(CACHE_DIR).bak" ]; then \
		echo "Error: No backup found at $(CACHE_DIR).bak"; \
		exit 1; \
	fi
	rm "$(CACHE_DIR)"
	mv "$(CACHE_DIR).bak" "$(CACHE_DIR)"
	@echo ""
	@echo "Restored cache from backup."
	@echo "Restart Claude Code to load the released version."

dsh-link:
	@bash "$(CURDIR)/scripts/build-dsh-skills.sh" "$(DSH_BUILD)"
	@mkdir -p "$(DSH_SKILLS)"
	@linked=0; skipped=0; adapted=0; \
	for dir in "$(CURDIR)"/skills/*/; do \
		src="$${dir%/}"; \
		name=$$(basename "$$src"); \
		if [ -d "$(DSH_BUILD)/$$name" ]; then \
			src="$(DSH_BUILD)/$$name"; \
			adapted=$$((adapted+1)); \
		fi; \
		target="$(DSH_SKILLS)/$$name"; \
		if [ -e "$$target" ] && [ ! -L "$$target" ]; then \
			echo "skip $$name: $$target exists and is not a symlink"; \
			skipped=$$((skipped+1)); \
			continue; \
		fi; \
		ln -sfn "$$src" "$$target"; \
		linked=$$((linked+1)); \
	done; \
	echo ""; \
	echo "Linked $$linked skill(s) into $(DSH_SKILLS), $$adapted adapted, $$skipped skipped."; \
	echo "DeepSeek Harness refreshes its catalog on the next turn; no restart needed."

dsh-unlink:
	@if [ ! -d "$(DSH_SKILLS)" ]; then \
		echo "Error: no DSH skill root at $(DSH_SKILLS)"; \
		exit 1; \
	fi
	@removed=0; \
	for dir in "$(CURDIR)"/skills/*/; do \
		src="$${dir%/}"; \
		name=$$(basename "$$src"); \
		target="$(DSH_SKILLS)/$$name"; \
		[ -L "$$target" ] || continue; \
		link=$$(readlink "$$target"); \
		if [ "$$link" = "$$src" ] || [ "$$link" = "$(DSH_BUILD)/$$name" ]; then \
			rm "$$target"; \
			removed=$$((removed+1)); \
		fi; \
	done; \
	if [ "$$removed" -eq 0 ]; then \
		echo "No links from $(CURDIR) found in $(DSH_SKILLS)"; \
	else \
		echo "Removed $$removed link(s) from $(DSH_SKILLS)"; \
	fi

dsh-install:
	@bash "$(CURDIR)/scripts/build-dsh-skills.sh" --all "$(DSH_BUILD)"
	@bash "$(CURDIR)/scripts/sync-dsh-skills.sh" install "$(DSH_BUILD)" "$(DSH_SKILLS)"
	@echo "DeepSeek Harness refreshes its catalog on the next turn; no restart needed."

dsh-remove:
	@bash "$(CURDIR)/scripts/sync-dsh-skills.sh" remove "$(DSH_SKILLS)"

validate:
	uvx skill-linter@0.2.0 release
	uvx skill-linter@0.2.0 stamp --check

test:
	bash scripts/test-makefile.sh
	bash scripts/test-build-plugin-dist.sh

site-dev:
	cd site && npm run dev

site-build:
	cd site && npm run build

lint:
	ruff check scripts/
	ruff format --check scripts/
	pyright scripts/
	cd site && npx prettier --plugin prettier-plugin-astro --check "src/**" "scripts/**" astro.config.mjs
	npx prettier --check "skills/**/*.md" "docs/**/*.md" "*.md" "research/**/*.md"

format:
	ruff check --fix scripts/
	ruff format scripts/
	cd site && npx prettier --plugin prettier-plugin-astro --write "src/**" "scripts/**" astro.config.mjs
	npx prettier --write "skills/**/*.md" "docs/**/*.md" "*.md" "research/**/*.md"

lint-fix: format
