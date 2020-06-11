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

files: $(BIN_T) $(SVC_T) $(DFL_T)


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
