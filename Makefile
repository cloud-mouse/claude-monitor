APP_NAME = ClaudeMonitor
BUNDLE_ID = com.claudemonitor.app
APP_BUNDLE = _DIST/$(APP_NAME).app

.PHONY: build build-arm64 build-x86_64 bundle bundle-universal clean install run

# Build for the current Mac's native architecture (fast, for development)
build:
	swift build -c release

# Build for Apple Silicon
build-arm64:
	swift build -c release --arch arm64 \
		--build-path .build/arm64

# Build for Intel
build-x86_64:
	swift build -c release --arch x86_64 \
		--build-path .build/x86_64

# Create Universal Binary by merging both architectures
EXEC_ARM64 = .build/arm64/release/$(APP_NAME)
EXEC_X86_64 = .build/x86_64/release/$(APP_NAME)
EXEC_UNIVERSAL = .build/universal/$(APP_NAME)

bundle-universal: build-arm64 build-x86_64
	@mkdir -p .build/universal
	lipo -create $(EXEC_ARM64) $(EXEC_X86_64) -output $(EXEC_UNIVERSAL)
	@echo "✅ Universal binary created (arm64 + x86_64)"
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(EXEC_UNIVERSAL) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
		echo "📋 Icon bundled"; \
	fi
	@codesign --force --sign - --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	@echo "✅ Universal app bundle created: $(APP_BUNDLE)"
	@lipo -archs $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) | xargs printf "📐 Architectures: %s\n"

# Default bundle: single-arch (arm64 only)
bundle: build
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then \
		cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; \
		echo "📋 Icon bundled"; \
	fi
	@# 整包 ad-hoc 签名（绑定 Info.plist、密封资源）。窗口切换靠 AppleScript 控制
	@# System Events / 其他进程，TCC 据此稳定识别本 app 身份以授权自动化权限；
	@# 仅 linker-signed 时身份不完整，安装版会静默被拒 → 激活到错误窗口。
	@codesign --force --sign - --identifier $(BUNDLE_ID) $(APP_BUNDLE)
	@echo "✅ App bundle created: $(APP_BUNDLE)"

install: bundle
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

install-universal: bundle-universal
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

# 必须运行 bundle 内的二进制：UNUserNotificationCenter 要求进程身处合法 .app
# bundle（依赖 mainBundle.bundleIdentifier 定位通知代理），裸二进制会在启动
# 即崩（bundleProxyForCurrentProcess is nil）。直接跑包内可执行文件而非 open，
# 这样 stdout/stderr 仍直连终端，便于开发调试。
run: bundle
	@./$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

clean:
	rm -rf .build _DIST

uninstall:
	rm -rf /Applications/$(APP_NAME).app
	@echo "✅ Uninstalled"
