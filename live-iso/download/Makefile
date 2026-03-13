ifeq ($(shell id -u),0)
	PREFIX ?= /usr/local
else
	PREFIX ?= $(HOME)
endif
BINDIR ?= $(PREFIX)/bin

install:
	@echo "Installing to $(DESTDIR)$(BINDIR)..."
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 agama-download-image $(DESTDIR)$(BINDIR)/agama-download-image
	install -m 0755 agama-image-dirs $(DESTDIR)$(BINDIR)/agama-image-dirs

uninstall:
	@echo "Removing $(DESTDIR)$(BINDIR)/agama-download-iso..."
	rm -f $(DESTDIR)$(BINDIR)/agama-download-iso
	rm -f $(DESTDIR)$(BINDIR)/agama-image-dirs

.PHONY: install uninstall
