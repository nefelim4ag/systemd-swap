PREFIX ?= /
FEDORA_VERSION ?= f32

default:  help

LIB_T  := $(PREFIX)/var/lib/systemd-swap
BIN_T  := $(PREFIX)/usr/bin/systemd-swap
SVC_T  := $(PREFIX)/lib/systemd/system/systemd-swap.service
DFL_T  := $(PREFIX)/usr/share/systemd-swap/swap-default.conf
CNF_T  := $(PREFIX)/etc/systemd/swap.conf


$(LIB_T):
	mkdir -p $@

dirs: $(LIB_T)

$(BIN_T): systemd-swap
	install -Dm755 $< $@

$(SVC_T): systemd-swap.service
	install -Dm644 $< $@

$(DFL_T): swap-default.conf
	install -bDm644 $< $@

$(CNF_T): swap.conf
	install -bDm644 -S .old $< $@

files: $(BIN_T) $(SVC_T) $(DFL_T) $(CNF_T)

define banner
#  This file is part of systemd-swap.\n#\n# Entries in this file show the systemd-swap defaults as\n# specified in /usr/share/systemd-swap/swap-default.conf\n# You can change settings by editing this file.\n# Defaults can be restored by simply deleting this file.\n#\n# See swap.conf(5) and /usr/share/systemd-swap/swap-default.conf for details.\n
endef
swap.conf:
	echo "$(banner)" > $@
	grep -o '^[^#]*' swap-default.conf | sed 's/^/#/' >> $@

install: ## Install systemd-swap
install: dirs files

uninstall: ## Delete systemd-swap (stop systemd-swap first)
uninstall:
	test ! -f /run/systemd/swap/swap.conf
	@rm -v $(BIN_T)
	@rm -v $(SVC_T)
	@rm -v $(DFL_T)
	@rm -v $(CNF_T)
	rm -r $(PREFIX)/var/lib/systemd-swap
	rmdir $(PREFIX)/usr/share/systemd-swap

deb: ## Create debian package
deb: package.sh
	./$< debian

rpm: ## Create fedora package
rpm: package.sh
	./$< fedora $(FEDORA_VERSION)

help: ## Show help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/\t/'
