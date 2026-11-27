# See docs/installation.md.
BINARY      := keytap
BUILT       := .build/release/$(BINARY)
INSTALL_DIR := /usr/local/bin
INSTALLED   := $(INSTALL_DIR)/$(BINARY)
# Where a new build waits while the installed one hands its secrets over; the path is fixed in the binary.
SUCCESSOR   := $(INSTALLED).new
CONFIG_DIR  := /usr/local/etc
CONFIG      := $(CONFIG_DIR)/$(BINARY).conf
CONFIG_SAMPLE := $(BINARY).conf.sample
COMPLETION_DIR := /usr/local/share/zsh/site-functions
COMPLETION  := $(COMPLETION_DIR)/_$(BINARY)
FORMAT_PATHS := Package.swift Sources Tests

# With only the Command Line Tools installed, SwiftPM does not find the Swift Testing macro plugin on its own.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.DEFAULT_GOAL := help
.PHONY: help build test lint format smoke sign install update verify uninstall purge clean

help:
	@echo "make build      build the release binary"
	@echo "make test       run the tests"
	@echo "make lint       check formatting and style"
	@echo "make format     format the sources in place"
	@echo "make smoke      run the built binary on cases that touch neither the Keychain nor the settings"
	@echo "make install    build, sign, install into $(INSTALL_DIR) (asks for sudo), verify"
	@echo "                with DESTDIR=<dir>: only copy the files under <dir>, for a package"
	@echo "make update     same as install; an installed build first hands its secrets over to the new one"
	@echo "make verify     check the installed binary and settings file"
	@echo "make uninstall  remove the binary, settings file and completion; secrets stay in the Keychain"
	@echo "make purge      delete every secret the tool stored, after you confirm"
	@echo "make clean      remove build products"

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive $(FORMAT_PATHS)

format:
	swift format format --in-place --recursive $(FORMAT_PATHS)

# Usage errors are caught before the settings file is read, so none of these needs an installation.
smoke: build
	@failed=0; \
	expect() { want=$$1; shift; "$(BUILT)" "$$@" >/dev/null 2>&1; got=$$?; \
		if [ $$got -eq $$want ]; then echo "ok    $(BINARY) $$* -> $$want"; \
		else echo "FAIL  $(BINARY) $$* -> $$got, expected $$want"; failed=1; fi; }; \
	expect 0 help; \
	expect 0 --version; \
	expect 2; \
	expect 2 frobnicate; \
	expect 2 get; \
	expect 2 get svc account extra; \
	expect 2 set --no-cache svc; \
	version=$$("$(BUILT)" --version | sed 's/^$(BINARY) //'); \
	if grep -q "^## \[$$version\]" CHANGELOG.md; then echo "ok    version $$version is in CHANGELOG.md"; \
	else echo "FAIL  version $$version is not in CHANGELOG.md"; failed=1; fi; \
	exit $$failed

# Hardened runtime keeps other processes from injecting code into the binary or attaching a debugger.
sign: build
	codesign --sign - --force --options runtime $(BUILT)

# The Keychain trusts a build by its signature, so a changed build could not read the secrets the installed one
# stored. The installed build therefore moves them to the new one before it is replaced.
# From the hand-over until the new build is in place, INT, TERM and HUP are ignored, so it cannot stop halfway.
# See docs/installation.md#updating.
# With DESTDIR set, the files are only staged under it for a package; see docs/installation.md#staging-for-a-package.
install: sign
ifdef DESTDIR
	install -d $(DESTDIR)$(INSTALL_DIR) $(DESTDIR)$(CONFIG_DIR) $(DESTDIR)$(COMPLETION_DIR)
	install -m 755 $(BUILT) $(DESTDIR)$(INSTALLED)
	install -m 644 $(CONFIG_SAMPLE) $(DESTDIR)$(CONFIG_DIR)/$(CONFIG_SAMPLE)
	install -m 644 completions/_$(BINARY) $(DESTDIR)$(COMPLETION)
	@echo "Staged under $(DESTDIR); nothing was installed on this Mac."
else
	@for directory in $(INSTALL_DIR) $(CONFIG_DIR) $(COMPLETION_DIR); do \
		if [ ! -d $$directory ]; then \
			echo "sudo install -d -o root -g wheel -m 755 $$directory"; \
			sudo install -d -o root -g wheel -m 755 $$directory; \
		fi; \
	done
	@if [ -e $(SUCCESSOR) ]; then \
		echo "sudo rm -f $(SUCCESSOR)"; \
		sudo rm -f $(SUCCESSOR); \
	fi
	@if [ ! -e $(INSTALLED) ] || cmp -s $(BUILT) $(INSTALLED); then \
		echo "sudo install -o root -g wheel -m 755 $(BUILT) $(INSTALLED)"; \
		sudo install -o root -g wheel -m 755 $(BUILT) $(INSTALLED); \
	else \
		echo "sudo install -o root -g wheel -m 755 $(BUILT) $(SUCCESSOR)"; \
		sudo install -o root -g wheel -m 755 $(BUILT) $(SUCCESSOR) || exit 1; \
		echo "The installed build hands its secrets over to the new one; confirm with Touch ID."; \
		trap '' INT TERM HUP; \
		if ! $(INSTALLED) handover; then \
			echo "sudo rm -f $(SUCCESSOR)"; \
			sudo rm -f $(SUCCESSOR); \
			echo "The update was stopped; the installed build stays in place."; \
			exit 1; \
		fi; \
		echo "sudo mv -f $(SUCCESSOR) $(INSTALLED)"; \
		sudo mv -f $(SUCCESSOR) $(INSTALLED); \
	fi
	@if [ ! -e $(CONFIG) ]; then \
		echo "sudo install -o root -g wheel -m 644 $(CONFIG_SAMPLE) $(CONFIG)"; \
		sudo install -o root -g wheel -m 644 $(CONFIG_SAMPLE) $(CONFIG); \
	fi
	@if ! cmp -s completions/_$(BINARY) $(COMPLETION); then \
		echo "sudo install -o root -g wheel -m 644 completions/_$(BINARY) $(COMPLETION)"; \
		sudo install -o root -g wheel -m 644 completions/_$(BINARY) $(COMPLETION); \
	fi
	@$(MAKE) --no-print-directory verify
endif

update: install

verify:
	@failed=0; \
	check() { if eval "$$2" >/dev/null 2>&1; then echo "ok    $$1"; else echo "FAIL  $$1"; failed=1; fi; }; \
	check "$(INSTALLED) exists" '[ -f $(INSTALLED) ]'; \
	check "binary is owned by root:wheel with mode 755" '[ "$$(stat -f "%Su:%Sg %Lp" $(INSTALLED))" = "root:wheel 755" ]'; \
	check "$(INSTALL_DIR) is owned by root and not writable by others" '[ "$$(stat -f "%Su" $(INSTALL_DIR))" = root ] && [ $$(( 0$$(stat -f "%Lp" $(INSTALL_DIR)) & 022 )) -eq 0 ]'; \
	check "signature is valid" 'codesign --verify --strict $(INSTALLED)'; \
	check "hardened runtime is enabled" 'codesign --display --verbose $(INSTALLED) 2>&1 | grep -q "flags=.*runtime"'; \
	check "'$(BINARY)' on PATH is the installed binary" '[ "$$(command -v $(BINARY))" = "$(INSTALLED)" ]'; \
	check "no unfinished update is left behind ($(SUCCESSOR))" '[ ! -e $(SUCCESSOR) ]'; \
	check "zsh completion is installed ($(COMPLETION))" '[ -f $(COMPLETION) ]'; \
	if [ -e $(CONFIG) ]; then \
		check "settings file is owned by root" '[ "$$(stat -f "%Su" $(CONFIG))" = root ]'; \
		check "settings file is not writable by group or others" '[ $$(( 0$$(stat -f "%Lp" $(CONFIG)) & 022 )) -eq 0 ]'; \
		check "settings file is valid" '$(INSTALLED) list'; \
	else \
		echo "ok    no settings file, defaults apply"; \
	fi; \
	exit $$failed

uninstall:
	@if [ -x $(INSTALLED) ]; then \
		echo "Secrets that stay in the Keychain (service, account):"; \
		$(INSTALLED) list || true; \
		echo "Remove them all with 'make purge', or one with: security delete-generic-password -s <service> -a <account>"; \
	fi
	sudo rm -f $(INSTALLED) $(SUCCESSOR) $(CONFIG) $(COMPLETION)

# Deleting a Keychain item needs no authentication, so the question guards only against a slip of the hand.
# Uses the installed build, or the built one after an uninstall. See docs/installation.md#deleting-every-secret.
purge:
	@tool=$(INSTALLED); [ -x "$$tool" ] || tool=$(BUILT); \
	if [ ! -x "$$tool" ]; then echo "No build of $(BINARY) to do it with; run 'make build' first."; exit 1; fi; \
	secrets=$$("$$tool" list) || exit 1; \
	if [ -z "$$secrets" ]; then echo "$(BINARY) has no secrets stored."; exit 0; fi; \
	echo "Secrets stored by $(BINARY) (service, account):"; \
	printf '%s\n' "$$secrets"; \
	printf 'Type "delete" to remove them all from the Keychain: '; \
	read -r answer; \
	if [ "$$answer" != delete ]; then echo "Nothing was removed."; exit 1; fi; \
	tab=$$(printf '\t'); \
	printf '%s\n' "$$secrets" | { \
		failed=0; \
		while IFS="$$tab" read -r service account; do \
			if "$$tool" delete -- "$$service" "$$account" </dev/null; then \
				printf 'removed  %s (%s)\n' "$$service" "$$account"; \
			else \
				failed=1; \
			fi; \
		done; \
		exit $$failed; \
	} || { echo "Not everything could be removed; what is left can be deleted in Keychain Access."; exit 1; }

clean:
	rm -rf .build
