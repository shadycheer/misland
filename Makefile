APP=misland
BUNDLE=.build/$(APP).app
BIN=.build/release/$(APP)

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - \
	  --entitlements Resources/misland.entitlements \
	  $(BUNDLE)/Contents/MacOS/$(APP)

run: bundle
	-killall $(APP) 2>/dev/null; sleep 0.3
	open -n $(BUNDLE)

test:
	swift test

dmg: bundle
	rm -f .build/$(APP).dmg
	rm -rf .build/dmg && mkdir -p .build/dmg
	cp -R $(BUNDLE) .build/dmg/
	ln -s /Applications .build/dmg/Applications
	hdiutil create -volname "MisLand" -srcfolder .build/dmg -ov -format UDZO .build/$(APP).dmg
	rm -rf .build/dmg
	@echo "→ .build/$(APP).dmg"

watch:
	@bash scripts/watch.sh

.PHONY: build bundle run test watch
