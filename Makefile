APP     = build/Therm2.app
DESTDIR = $(HOME)/Applications
.PHONY: all debug run prepare test icons install uninstall sign clean

all:
	./scripts/build.sh release

debug:
	./scripts/build.sh debug

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

clean:
	swift package clean
	rm -rf build
