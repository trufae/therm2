APP     = build/Therm2.app
DESTDIR = /Applications
.PHONY: all debug dmg run prepare test icons install uninstall sign clean

all:
	./scripts/build.sh release

debug:
	./scripts/build.sh debug

dmg:
	./scripts/package-dmg.sh

run: all
	open $(APP)

prepare:
	./scripts/prepare-deps.sh

test:
	./scripts/test.sh

icons:
	./scripts/generate-icons.sh

sign: all
	codesign --force --sign - $(APP)

install: all
	mkdir -p $(DESTDIR)
	rm -rf $(DESTDIR)/Therm2.app
	cp -R $(APP) $(DESTDIR)/Therm2.app

uninstall:
	rm -rf $(DESTDIR)/Therm2.app

user-install:
	$(MAKE) install DESTDIR=$(HOME)/Applications

user-uninstall:
	$(MAKE) uninstall DESTDIR=$(HOME)/Applications

clean:
	swift package clean
	rm -rf build
