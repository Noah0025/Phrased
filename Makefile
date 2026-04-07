APP_NAME = Phrased
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app

.PHONY: build run package clean

build:
	swift build -c release 2>&1

run:
	swift run 2>&1

package: build
	@echo "==> Packaging $(APP_BUNDLE)..."
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/Phrased $(APP_BUNDLE)/Contents/MacOS/Phrased
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@rm -rf $(APP_BUNDLE)/Contents/Resources/en.lproj $(APP_BUNDLE)/Contents/Resources/zh-Hans.lproj
	@cp -r $(BUILD_DIR)/Phrased_Phrased.bundle/en.lproj $(APP_BUNDLE)/Contents/Resources/en.lproj
	@cp -r $(BUILD_DIR)/Phrased_Phrased.bundle/zh-hans.lproj $(APP_BUNDLE)/Contents/Resources/zh-Hans.lproj
	@codesign --force --deep --sign - --entitlements Phrased.entitlements $(APP_BUNDLE)
	@echo "==> Done: $(APP_BUNDLE)"

open: package
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
