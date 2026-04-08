APP_NAME    = Phrased
VERSION     = 1.0
BUILD_DIR   = .build/release
APP_BUNDLE  = $(APP_NAME).app
DMG_NAME    = $(APP_NAME)-$(VERSION).dmg
DMG_STAGING = .dmg-staging

.PHONY: build run package dmg open clean

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
	@cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@codesign --force --deep --sign - --entitlements Phrased.entitlements $(APP_BUNDLE)
	@echo "==> Done: $(APP_BUNDLE)"

dmg: package
	@echo "==> Creating $(DMG_NAME)..."
	@rm -rf $(DMG_STAGING) $(DMG_NAME)
	@mkdir -p $(DMG_STAGING)
	@cp -r $(APP_BUNDLE) $(DMG_STAGING)/
	@ln -s /Applications $(DMG_STAGING)/Applications
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder $(DMG_STAGING) \
		-ov \
		-format UDZO \
		-fs HFS+ \
		$(DMG_NAME)
	@rm -rf $(DMG_STAGING)
	@echo "==> Done: $(DMG_NAME)"

open: package
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(DMG_NAME) $(DMG_STAGING)
