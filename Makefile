# See docs/installation.md.
BINARY      := keychain-touchid
BUILT       := .build/release/$(BINARY)
INSTALL_DIR := /usr/local/bin
INSTALLED   := $(INSTALL_DIR)/$(BINARY)
CONFIG_DIR  := /usr/local/etc
CONFIG      := $(CONFIG_DIR)/$(BINARY).conf
CONFIG_SAMPLE := $(BINARY).conf.sample

# With only the Command Line Tools installed, SwiftPM does not find the Swift Testing macro plugin on its own.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.DEFAULT_GOAL := help
.PHONY: help build test sign install update verify uninstall clean

help:
	@echo "make build      build the release binary"
	@echo "make test       run the tests"
	@echo "make install    build, sign, install into $(INSTALL_DIR) (asks for sudo), verify"
	@echo "make update     same as install"
	@echo "make verify     check the installed binary and settings file"
	@echo "make uninstall  remove the binary and settings file; secrets stay in the Keychain"
	@echo "make clean      remove build products"

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

# Hardened runtime keeps other processes from injecting code into the binary or attaching a debugger.
sign: build
	codesign --sign - --force --options runtime $(BUILT)

install: sign
	@if [ -e $(INSTALLED) ] && ! cmp -s $(BUILT) $(INSTALLED); then \
		echo "This build differs from the installed one, so the Keychain treats it as a new program:"; \
		echo "the first read of each secret asks for the Mac password once (choose Always Allow),"; \
		echo "or store the secret again with 'delete' and 'set'."; \
	fi
	@for directory in $(INSTALL_DIR) $(CONFIG_DIR); do \
		if [ ! -d $$directory ]; then \
			echo "sudo install -d -o root -g wheel -m 755 $$directory"; \
			sudo install -d -o root -g wheel -m 755 $$directory; \
		fi; \
	done
	sudo install -o root -g wheel -m 755 $(BUILT) $(INSTALLED)
	@if [ ! -e $(CONFIG) ]; then \
		echo "sudo install -o root -g wheel -m 644 $(CONFIG_SAMPLE) $(CONFIG)"; \
		sudo install -o root -g wheel -m 644 $(CONFIG_SAMPLE) $(CONFIG); \
	fi
	@$(MAKE) --no-print-directory verify

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
		echo "Remove one with: security delete-generic-password -s <service> -a <account>"; \
	fi
	sudo rm -f $(INSTALLED) $(CONFIG)

clean:
	rm -rf .build
