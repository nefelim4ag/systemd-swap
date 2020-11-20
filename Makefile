prefix ?= $(PREFIX)

# this avoids /usr/local/usr/* when
# installing with prefix=/usr/local
ifeq ($(prefix), /usr/local)
exec_prefix ?= $(prefix)
datarootdir ?= $(prefix)/share
else
exec_prefix ?= $(prefix)/usr
datarootdir ?= $(prefix)/usr/share
endif

bindir ?= $(exec_prefix)/bin
libdir ?= $(exec_prefix)/lib
datadir ?= $(datarootdir)
mandir ?= $(datarootdir)/man

sysconfdir ?= $(prefix)/etc
localstatedir ?= $(prefix)/var

FEDORA_VERSION ?= f33

GITB := $(shell command -v git 2>/dev/null)
ifdef GITB
REPO := $(shell git rev-parse --is-inside-work-tree 2>/dev/null)
endif

ifneq ($(strip $(prefix)),)
PATCH := true
endif

LIB_T := $(DESTDIR)$(localstatedir)/lib/systemd-swap
BIN_T := $(DESTDIR)$(bindir)/systemd-swap
SVC_T := $(DESTDIR)$(libdir)/systemd/system/systemd-swap.service
DFL_T := $(DESTDIR)$(datadir)/systemd-swap/swap-default.conf
CNF_T := $(DESTDIR)$(sysconfdir)/systemd/swap.conf
MAN5_T := $(DESTDIR)$(mandir)/man5/swap.conf.5
MAN8_T := $(DESTDIR)$(mandir)/man8/systemd-swap.8

.PHONY: files dirs install uninstall clean deb rpm help reformat stylecheck stylediff

default: help

$(LIB_T):
	mkdir -p $@

dirs: $(LIB_T)

$(BIN_T): src/systemd-swap.py
ifdef PATCH
	@echo '** Patching prefix in systemd-swap..'
	@sed -e 's#ETC_SYSD = "/etc/systemd"#ETC_SYSD = "$(sysconfdir)/systemd"#' \
		-e 's#VEN_SYSD = "/usr/lib/systemd"#VEN_SYSD = "$(libdir)/systemd"#' \
		-e 's#DEF_CONFIG = "/usr/share/systemd-swap/swap-default.conf"#DEF_CONFIG = "$(datarootdir)/systemd-swap/swap-default.conf"#' \
	 	$< > systemd-swap.new
	install -p -Dm755 systemd-swap.new $@
else
	install -p -Dm755 $< $@
endif

$(SVC_T): include/systemd-swap.service
ifdef PATCH
	@echo '** Patching prefix in systemd-swap.service..'
	@sed 's#/usr/bin/systemd-swap#$(bindir)/systemd-swap#g' $< > systemd-swap.service.new
	install -p -Dm644 systemd-swap.service.new $@
else
	install -p -Dm644 $< $@
endif

$(DFL_T): include/swap-default.conf
	install -p -Dm644 $< $@

$(CNF_T): swap.conf
	install -p -bDm644 -S .old $< $@

$(MAN5_T): man/swap.conf.5
	install -p -Dm644 $< $@

$(MAN8_T): man/systemd-swap.8
	install -p -Dm644 $< $@

define banner
#  This file is part of systemd-swap.\n#\n# Entries in this file show the systemd-swap defaults as\n# specified in $(datarootdir)/systemd-swap/swap-default.conf\n# You can change settings by editing this file.\n# Defaults can be restored by simply deleting this file.\n#\n# See swap.conf(5) and $(datarootdir)/systemd-swap/swap-default.conf for details.\n\n
endef

swap.conf: ## Generate swap.conf
	@echo '** Generating swap.conf..'
	@printf "$(banner)" > $@
	@grep -o '^[^#]*' include/swap-default.conf | sed 's/^/#/;s/[ \t]*$$//' >> $@

files: $(BIN_T) $(SVC_T) $(DFL_T) $(CNF_T) $(MAN5_T) $(MAN8_T)

install: ## Install systemd-swap
install: dirs files

uninstall: ## Delete systemd-swap (stop systemd-swap first)
uninstall:
	test ! -f /run/systemd/swap/swap.conf
	rm -v $(BIN_T) $(SVC_T) $(DFL_T) $(CNF_T) $(MAN5_T) $(MAN8_T)
	rm -rv $(LIB_T) $(DESTDIR)$(datadir)/systemd-swap

clean: ## Remove generated files
ifdef REPO
	git clean -fxd
else
	rm -vf swap.conf *.new
endif

deb: ## Create debian package
deb: contrib/package.sh
	./$< debian

rpm: ## Create fedora package
rpm: contrib/package.sh
	./$< fedora $(FEDORA_VERSION)

# Python Code Style
reformat: ## Format code
	python -m black src/systemd-swap.py
stylecheck: ## Check codestyle
	python -m black --check src/systemd-swap.py
stylediff: ## Diff codestyle changes
	python -m black --check --diff src/systemd-swap.py

help: ## Show help
	@grep -h "##" $(MAKEFILE_LIST) | grep -v grep | sed 's/\\$$//;s/##/\t/'
