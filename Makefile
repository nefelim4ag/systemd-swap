PREFIX ?= /

default:  help

install: ## Install systemd-swap
install:
	install -Dm755	./systemd-swap 			$(PREFIX)/usr/bin/systemd-swap
	install -Dm644	./systemd-swap.service  $(PREFIX)/usr/lib/systemd/system/systemd-swap.service
	install -bDm644 -S .old	./swap.conf		$(PREFIX)/etc/systemd/swap.conf

uninstall: ## Delete systemd-swap (stop systemd-swap first)
uninstall:
	test ! -f /run/systemd/swap/swap.conf
	rm -v $(PREFIX)/usr/bin/systemd-swap
	rm -v $(PREFIX)/usr/lib/systemd/system/systemd-swap.service
	rm -v $(PREFIX)/etc/systemd/swap.conf

deb: ## Create debian package
deb:
	./package.sh debian

help: ## Show help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/\t/'
