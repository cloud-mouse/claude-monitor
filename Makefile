APP_NAME = ClaudeMonitor
BUNDLE_ID = com.claudemonitor.app
APP_BUNDLE = _DIST/$(APP_NAME).app
EXECUTABLE = .build/release/$(APP_NAME)

.PHONY: build bundle clean install run

build:
	swift build -c release --arch arm64

bundle: build
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(EXECUTABLE) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
		echo "📋 Icon bundled"; \
	fi
	@echo "✅ App bundle created: $(APP_BUNDLE)"

install: bundle
	@cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

run: build
	@./$(EXECUTABLE)

clean:
	rm -rf .build _DIST

uninstall:
	rm -rf /Applications/$(APP_NAME).app
	@echo "✅ Uninstalled"
