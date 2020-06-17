prefix			?= $(PREFIX)

# this avoids /usr/local/usr/* when
# installing with prefix=/usr/local
ifeq ($(prefix), /usr/local)
exec_prefix		?= $(prefix)
datarootdir		?= $(prefix)/share
else
exec_prefix		?= $(prefix)/usr
datarootdir		?= $(prefix)/usr/share
endif

bindir			?= $(exec_prefix)/bin
libdir			?= $(exec_prefix)/lib
datadir			?= $(datarootdir)
mandir			?= $(datarootdir)/man

sysconfdir		?= $(prefix)/etc
localstatedir	?= $(prefix)/var

FEDORA_VERSION 	?= f32
GIT := $(shell command -v git 2> /dev/null)

default: help

LIB_T := $(DESTDIR)$(localstatedir)/lib/systemd-swap
BIN_T := $(DESTDIR)$(bindir)/systemd-swap
SVC_T := $(DESTDIR)$(libdir)/systemd/system/systemd-swap.service
DFL_T := $(DESTDIR)$(datadir)/systemd-swap/swap-default.conf
CNF_T := $(DESTDIR)$(sysconfdir)/systemd/swap.conf
MAN5_T := $(DESTDIR)$(mandir)/man5/swap.conf.5
MAN8_T := $(DESTDIR)$(mandir)/man8/systemd-swap.8

.PHONY: files dirs install uninstall clean deb rpm help

$(LIB_T):
	mkdir -p $@

dirs: $(LIB_T)

$(BIN_T): systemd-swap
	install -Dm755 $< $@

$(SVC_T): systemd-swap.service
	install -Dm644 $< $@

$(DFL_T): swap-default.conf
	install -Dm644 $< $@

$(CNF_T): swap.conf
	install -bDm644 -S .old $< $@

$(MAN5_T): man/swap.conf.5
	install -Dm644 $< $@

$(MAN8_T): man/systemd-swap.8
	install -Dm644 $< $@

define banner
#  This file is part of systemd-swap.\n#\n# Entries in this file show the systemd-swap defaults as\n# specified in /usr/share/systemd-swap/swap-default.conf\n# You can change settings by editing this file.\n# Defaults can be restored by simply deleting this file.\n#\n# See swap.conf(5) and /usr/share/systemd-swap/swap-default.conf for details.\n\n
endef

swap.conf: ## Generate swap.conf
	@printf "$(banner)" > $@
	@grep -o '^[^#]*' swap-default.conf | sed 's/^/#/;s/[ \t]*$$//' >> $@

files: $(BIN_T) $(SVC_T) $(DFL_T) $(CNF_T) $(MAN5_T) $(MAN8_T)

install: ## Install systemd-swap
install: dirs files

uninstall: ## Delete systemd-swap (stop systemd-swap first)
uninstall:
	test ! -f /run/systemd/swap/swap.conf
	rm -v $(BIN_T) $(SVC_T) $(DFL_T) $(CNF_T) $(MAN5_T) $(MAN8_T)
	rm -rv $(LIB_T) $(DESTDIR)$(datadir)/systemd-swap

clean: ## Remove generated files
ifdef GIT
	git clean -fxd
endif
	rm -vf swap.conf

deb: ## Create debian package
deb: package.sh
	./$< debian

rpm: ## Create fedora package
rpm: package.sh
	./$< fedora $(FEDORA_VERSION)

help: ## Show help
	@grep -h "##" $(MAKEFILE_LIST) | grep -v grep | sed 's/\\$$//;s/##/\t/'
