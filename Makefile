APP=misland
BUNDLE=.build/$(APP).app
BIN=.build/release/$(APP)
DEV_BUNDLE=.build/$(APP)-dev.app
DEV_BIN=.build/debug/$(APP)
MEDIAREMOTE_ADAPTER_DIR=tools/mediaremote-adapter
MEDIAREMOTE_ADAPTER_FRAMEWORK=$(MEDIAREMOTE_ADAPTER_DIR)/build/MediaRemoteAdapter.framework
MEDIAREMOTE_ADAPTER_SCRIPT=$(MEDIAREMOTE_ADAPTER_DIR)/bin/mediaremote-adapter.pl

# Prefer a stable Apple Development identity so TCC grants (Accessibility,
# Automation) PERSIST across rebuilds. Falls back to ad-hoc (e.g. on CI, where
# no such identity exists), which is fine for distribution but resets TCC.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $$2}')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID = -
endif

build:
	swift build -c release

dev-build:
	swift build

mediaremote-adapter:
	@if [ ! -d "$(MEDIAREMOTE_ADAPTER_DIR)/.git" ]; then \
	  rm -rf "$(MEDIAREMOTE_ADAPTER_DIR)"; \
	  git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git "$(MEDIAREMOTE_ADAPTER_DIR)"; \
	fi
	cmake -S "$(MEDIAREMOTE_ADAPTER_DIR)" -B "$(MEDIAREMOTE_ADAPTER_DIR)/build" -DCMAKE_BUILD_TYPE=Release
	cmake --build "$(MEDIAREMOTE_ADAPTER_DIR)/build" --config Release

bundle: build mediaremote-adapter
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(BUNDLE)/Contents/Frameworks
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp -R "$(MEDIAREMOTE_ADAPTER_FRAMEWORK)" "$(BUNDLE)/Contents/Frameworks/MediaRemoteAdapter.framework"
	cp "$(MEDIAREMOTE_ADAPTER_SCRIPT)" "$(BUNDLE)/Contents/Resources/mediaremote-adapter.pl"
	@echo "codesign identity: $(SIGN_ID)"
	codesign --force --deep --sign "$(SIGN_ID)" \
	  --entitlements Resources/misland.entitlements \
	  $(BUNDLE)

dev-bundle: dev-build mediaremote-adapter
	rm -rf $(DEV_BUNDLE)
	mkdir -p $(DEV_BUNDLE)/Contents/MacOS $(DEV_BUNDLE)/Contents/Resources $(DEV_BUNDLE)/Contents/Frameworks
	cp $(DEV_BIN) $(DEV_BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(DEV_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(DEV_BUNDLE)/Contents/Resources/AppIcon.icns
	cp -R "$(MEDIAREMOTE_ADAPTER_FRAMEWORK)" "$(DEV_BUNDLE)/Contents/Frameworks/MediaRemoteAdapter.framework"
	cp "$(MEDIAREMOTE_ADAPTER_SCRIPT)" "$(DEV_BUNDLE)/Contents/Resources/mediaremote-adapter.pl"
	@echo "codesign identity: $(SIGN_ID)"
	codesign --force --deep --sign "$(SIGN_ID)" \
	  --entitlements Resources/misland.entitlements \
	  $(DEV_BUNDLE)

run: bundle
	-killall $(APP) 2>/dev/null; sleep 0.3
	open -n $(BUNDLE)

dev-run: dev-bundle
	-killall $(APP) 2>/dev/null; sleep 0.2
	open -n $(DEV_BUNDLE)

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

.PHONY: build dev-build mediaremote-adapter bundle dev-bundle run dev-run test watch
