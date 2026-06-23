APP=misland
BUNDLE=.build/$(APP).app
BIN=.build/release/$(APP)

# Prefer a stable Apple Development identity so TCC grants (Accessibility,
# Automation) PERSIST across rebuilds. Falls back to ad-hoc (e.g. on CI, where
# no such identity exists), which is fine for distribution but resets TCC.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $$2}')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID = -
endif

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "codesign identity: $(SIGN_ID)"
	codesign --force --deep --sign "$(SIGN_ID)" \
	  --entitlements Resources/misland.entitlements \
	  $(BUNDLE)

run: bundle
	-killall $(APP) 2>/dev/null; sleep 0.3
	open -n $(BUNDLE)

test:
	swift test

dmg: bundle
	rm -f .build/$(APP).dmg
	rm -rf .build/dmgsrc && mkdir -p .build/dmgsrc
	cp -R $(BUNDLE) ".build/dmgsrc/MisLand.app"
	@if command -v create-dmg >/dev/null 2>&1; then \
	  create-dmg \
	    --volname "MisLand" \
	    --window-size 560 380 \
	    --icon-size 120 \
	    --icon "MisLand.app" 150 185 \
	    --app-drop-link 410 185 \
	    --hide-extension "MisLand.app" \
	    --no-internet-enable \
	    ".build/$(APP).dmg" ".build/dmgsrc" ; \
	else \
	  echo "create-dmg not found — plain DMG fallback"; \
	  ln -s /Applications .build/dmgsrc/Applications; \
	  hdiutil create -volname "MisLand" -srcfolder .build/dmgsrc -ov -format UDZO ".build/$(APP).dmg"; \
	fi
	rm -rf .build/dmgsrc
	@echo "→ .build/$(APP).dmg"

watch:
	@bash scripts/watch.sh

.PHONY: build bundle run test watch
