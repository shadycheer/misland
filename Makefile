APP=NotchIsland
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
	  --entitlements Resources/NotchIsland.entitlements \
	  $(BUNDLE)/Contents/MacOS/$(APP)

run: bundle
	-killall $(APP) 2>/dev/null; sleep 0.3
	open -n $(BUNDLE)

test:
	swift test

.PHONY: build bundle run test
