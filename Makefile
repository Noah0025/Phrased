APP_NAME = Murmur
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
	@cp $(BUILD_DIR)/Murmur $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign "Murmur Dev" --entitlements Murmur.entitlements $(APP_BUNDLE)
	@echo "==> Done: $(APP_BUNDLE)"

open: package
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
