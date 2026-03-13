ifeq ($(shell id -u),0)
	PREFIX ?= /usr/local
else
	PREFIX ?= $(HOME)
endif
BINDIR ?= $(PREFIX)/bin

install:
	@echo "Installing to $(DESTDIR)$(BINDIR)..."
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 agama-iso-builder $(DESTDIR)$(BINDIR)/agama-iso-builder

uninstall:
	@echo "Removing $(DESTDIR)$(BINDIR)/agama-download-iso..."
	rm -f $(DESTDIR)$(BINDIR)/agama-iso-builder

.PHONY: install uninstall
