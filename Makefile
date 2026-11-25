PACKAGE := luci-app-simmanager
VERSION ?= 1.3.1
RELEASE ?= 1
ROUTER ?= mathansims-local
SCP_FLAGS ?= -O
IPK := dist/$(PACKAGE)_$(VERSION)-$(RELEASE)_all.ipk

.PHONY: build verify install uninstall clean

build:
	VERSION="$(VERSION)" RELEASE="$(RELEASE)" ./scripts/build-ipk.sh

verify:
	./scripts/verify.sh

install: build
	scp $(SCP_FLAGS) "$(IPK)" "$(ROUTER):/tmp/$(notdir $(IPK))"
	ssh "$(ROUTER)" "opkg install /tmp/$(notdir $(IPK))"

uninstall:
	ssh "$(ROUTER)" "opkg remove $(PACKAGE)"

clean:
	rm -rf dist

