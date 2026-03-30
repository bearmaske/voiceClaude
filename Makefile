APP_NAME = VoiceClaude
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
FRAMEWORKS_DIR = $(CONTENTS_DIR)/Frameworks

SHERPA_VERSION = 1.12.34
SHERPA_ARCHIVE = sherpa-onnx-v$(SHERPA_VERSION)-osx-universal2-shared.tar.bz2
SHERPA_URL = https://github.com/k2-fsa/sherpa-onnx/releases/download/v$(SHERPA_VERSION)/$(SHERPA_ARCHIVE)
DEPS_DIR = Dependencies/sherpa-onnx

.PHONY: build run install clean deps

deps:
	@if [ ! -d "$(DEPS_DIR)/lib" ]; then \
		echo "Downloading sherpa-onnx v$(SHERPA_VERSION)..."; \
		mkdir -p Dependencies; \
		curl -L -o /tmp/$(SHERPA_ARCHIVE) $(SHERPA_URL); \
		tar xjf /tmp/$(SHERPA_ARCHIVE) -C Dependencies/; \
		mv Dependencies/sherpa-onnx-v$(SHERPA_VERSION)-osx-universal2-shared $(DEPS_DIR); \
		rm -f /tmp/$(SHERPA_ARCHIVE); \
		echo "sherpa-onnx downloaded to $(DEPS_DIR)"; \
	else \
		echo "sherpa-onnx already downloaded"; \
	fi

build: deps
	swift build -c release
	mkdir -p $(MACOS_DIR) $(RESOURCES_DIR) $(FRAMEWORKS_DIR)
	cp .build/release/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	echo -n "APPL????" > $(CONTENTS_DIR)/PkgInfo
	# Bundle sherpa-onnx dylibs
	cp $(DEPS_DIR)/lib/libsherpa-onnx-c-api.dylib $(FRAMEWORKS_DIR)/
	cp $(DEPS_DIR)/lib/libonnxruntime.1.23.2.dylib $(FRAMEWORKS_DIR)/
	cd $(FRAMEWORKS_DIR) && ln -sf libonnxruntime.1.23.2.dylib libonnxruntime.dylib
	# Fix dylib rpaths
	install_name_tool -change @rpath/libonnxruntime.1.23.2.dylib @executable_path/../Frameworks/libonnxruntime.1.23.2.dylib $(FRAMEWORKS_DIR)/libsherpa-onnx-c-api.dylib 2>/dev/null || true
	install_name_tool -id @executable_path/../Frameworks/libsherpa-onnx-c-api.dylib $(FRAMEWORKS_DIR)/libsherpa-onnx-c-api.dylib 2>/dev/null || true
	install_name_tool -id @executable_path/../Frameworks/libonnxruntime.1.23.2.dylib $(FRAMEWORKS_DIR)/libonnxruntime.1.23.2.dylib 2>/dev/null || true
	xattr -cr $(APP_BUNDLE)
	codesign --force --sign - --deep $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

install: build
	cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf $(BUILD_DIR)
	@echo "Cleaned"

clean-all: clean
	rm -rf Dependencies
	@echo "Cleaned all (including dependencies)"
