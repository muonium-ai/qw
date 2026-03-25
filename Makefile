# QW — Makefile
# Build system for QW text editor
# Supports macOS, iOS (iPhone), and iPadOS (iPad)

# Project Configuration
PROJECT_DIR := qw
PROJECT_NAME := qw
XCODEPROJ := $(PROJECT_DIR)/$(PROJECT_NAME).xcodeproj
SCHEME := qw
TEAM_ID := 3CSC2UMR4Q

# Build directories
BUILD_DIR := build
DERIVED_DATA_MAC := $(BUILD_DIR)/DerivedData-mac
DERIVED_DATA_IOS := $(BUILD_DIR)/DerivedData-ios
DERIVED_DATA_IPAD := $(BUILD_DIR)/DerivedData-ipad

# CLI export tool
QW_EXPORT_DIR := qw-export

# Deployment targets
MACOS_DEPLOYMENT_TARGET := 15.0
IOS_DEPLOYMENT_TARGET := 18.0

# App icon source
ICON_SOURCE := requirements/qw_logo.png
ICON_DIR := $(PROJECT_DIR)/$(PROJECT_NAME)/Assets.xcassets/AppIcon.appiconset

# Simulator destinations
MAC_DESTINATION := "platform=macOS"
IPHONE_SIMULATOR_NAME := $(shell xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPhone/ {print $$1; exit}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//')
IPAD_SIMULATOR_NAME := $(shell xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPad/ {print $$1; exit}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//')
# NOTE: simctl output often includes multiple parenthesized fields, e.g.
#   iPad (A16) (<UDID>) (Shutdown)
# so we extract the UUID-like UDID via regex rather than assuming a fixed field index.
IPHONE_SIMULATOR_ID := $(shell xcrun simctl list devices available 2>/dev/null | awk '/iPhone/ { if (match($$0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) { print substr($$0, RSTART, RLENGTH); exit } }')
IPAD_SIMULATOR_ID := $(shell xcrun simctl list devices available 2>/dev/null | awk '/iPad/ { if (match($$0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) { print substr($$0, RSTART, RLENGTH); exit } }')

ifeq ($(strip $(IPHONE_SIMULATOR_NAME)),)
IPHONE_SIMULATOR_NAME := iPhone 17
endif
ifneq ($(strip $(IPHONE_SIMULATOR_ID)),)
IPHONE_DESTINATION := "platform=iOS Simulator,id=$(IPHONE_SIMULATOR_ID)"
else
IPHONE_DESTINATION := "platform=iOS Simulator,name=$(IPHONE_SIMULATOR_NAME)"
endif

ifneq ($(strip $(IPAD_SIMULATOR_ID)),)
IPAD_DESTINATION := "platform=iOS Simulator,id=$(IPAD_SIMULATOR_ID)"
else ifneq ($(strip $(IPAD_SIMULATOR_NAME)),)
IPAD_DESTINATION := "platform=iOS Simulator,name=$(IPAD_SIMULATOR_NAME)"
endif

# Device destinations (for actual devices)
IPHONE_DEVICE := "platform=iOS,name=iPhone"
IPAD_DEVICE := "platform=iOS,name=iPad"

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: all clean build build-mac build-ios build-ipad build-all \
	build-cli run-cli \
	deploy deploy-mac deploy-ios deploy-ipad \
	test run run-ios run-ipad icons help check-tools install install-cli uninstall

# Default target
all: build-all

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------
help:
	@echo "$(GREEN)QW Build System$(NC)"
	@echo "================"
	@echo ""
	@echo "$(YELLOW)Build Targets:$(NC)"
	@echo "  make build-mac    - Build for macOS"
	@echo "  make build-ios    - Build for iPad (alias for build-ipad)"
	@echo "  make build-ipad   - Build for iPad only"
	@echo "  make build-all    - Build for all platforms"
	@echo ""
	@echo "$(YELLOW)Deploy Targets:$(NC)"
	@echo "  make deploy-mac   - Build and run on macOS"
	@echo "  make deploy-ios   - Deploy to iPad Simulator (alias for deploy-ipad)"
	@echo "  make deploy-ipad  - Build and deploy to iPad Simulator"
	@echo "  make deploy       - Deploy to all platforms"
	@echo ""
	@echo "$(YELLOW)Run Targets:$(NC)"
	@echo "  make run          - Build and run GUI app on macOS"
	@echo "  make run-cli      - Build and run CLI export tool (shows help)"
	@echo "  make run-ios      - Run on iPad Simulator (alias for run-ipad)"
	@echo "  make run-ipad     - Build and run on iPad Simulator"
	@echo ""
	@echo "$(YELLOW)Other Targets:$(NC)"
	@echo "  make build-cli    - Build the qw-export CLI tool"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make test         - Run unit tests"
	@echo "  make icons        - Generate app icons from qw_logo.png"
	@echo "  make check-tools  - Verify required tools are installed"
	@echo ""
	@echo "$(YELLOW)Installation:$(NC)"
	@echo "  make install      - Install app to /Applications and CLI to /usr/local/bin"
	@echo "  make install-cli  - Install only the 'qw' command line tool"
	@echo "  make uninstall    - Remove app and CLI tool"
	@echo ""
	@echo "$(YELLOW)CLI Usage (after make install):$(NC)"
	@echo "  qw                      - Open QW Editor GUI"
	@echo "  qw file.txt             - Open a file in GUI"
	@echo "  qw --pdf file.py        - Export file to PDF"
	@echo "  qw --png file.py        - Export file to PNG"
	@echo "  qw -h                   - Show CLI help"
	@echo ""
	@echo "$(YELLOW)CLI Export Tool (standalone):$(NC)"
	@echo "  make run-cli            - Show qw-export help"
	@echo "  .build/release/qw-export --pdf file.py  - Export to PDF"
	@echo ""

#------------------------------------------------------------------------------
# Tool Checks
#------------------------------------------------------------------------------
check-tools:
	@echo "$(YELLOW)Checking required tools...$(NC)"
	@which xcodebuild > /dev/null || (echo "$(RED)Error: xcodebuild not found$(NC)" && exit 1)
	@which sips > /dev/null || (echo "$(RED)Error: sips not found$(NC)" && exit 1)
	@echo "$(GREEN)All tools available$(NC)"

#------------------------------------------------------------------------------
# Build CLI Export Tool (Swift Package)
#------------------------------------------------------------------------------
build-cli:
	@echo "$(YELLOW)Building qw-export CLI tool...$(NC)"
	@cd $(QW_EXPORT_DIR) && swift build -c release 2>&1 | tail -5
	@echo "$(GREEN)CLI build complete: $(QW_EXPORT_DIR)/.build/release/qw-export$(NC)"

#------------------------------------------------------------------------------
# Run CLI Export Tool
#------------------------------------------------------------------------------
run-cli: build-cli
	@cd $(QW_EXPORT_DIR) && .build/release/qw-export --help

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(PROJECT_NAME)-*
	@rm -rf $(QW_EXPORT_DIR)/.build
	@xcodebuild clean \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-quiet 2>/dev/null || true
	@echo "$(GREEN)Clean complete$(NC)"

#------------------------------------------------------------------------------
# Icon Generation
#------------------------------------------------------------------------------
icons:
	@echo "$(YELLOW)Generating app icons from $(ICON_SOURCE)...$(NC)"
	@if [ ! -f "$(ICON_SOURCE)" ]; then \
		echo "$(RED)Error: $(ICON_SOURCE) not found$(NC)"; \
		exit 1; \
	fi
	@mkdir -p $(ICON_DIR)
	
	# iOS Universal (1024x1024)
	@sips -z 1024 1024 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_1024x1024.png" 2>/dev/null
	
	# macOS icons
	@sips -z 16 16 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_16x16.png" 2>/dev/null
	@sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_16x16@2x.png" 2>/dev/null
	@sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_32x32.png" 2>/dev/null
	@sips -z 64 64 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_32x32@2x.png" 2>/dev/null
	@sips -z 128 128 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_128x128.png" 2>/dev/null
	@sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_128x128@2x.png" 2>/dev/null
	@sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_256x256.png" 2>/dev/null
	@sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_256x256@2x.png" 2>/dev/null
	@sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_512x512.png" 2>/dev/null
	@sips -z 1024 1024 "$(ICON_SOURCE)" --out "$(ICON_DIR)/icon_512x512@2x.png" 2>/dev/null
	
	@echo "$(GREEN)App icons generated successfully$(NC)"
	@echo "$(YELLOW)Remember to update Contents.json with the new filenames$(NC)"

#------------------------------------------------------------------------------
# Build for macOS
#------------------------------------------------------------------------------
build-mac: check-tools
	@echo "$(YELLOW)Building for macOS...$(NC)"
	@mkdir -p $(BUILD_DIR)/mac
	@set -o pipefail; \
	xcodebuild build \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(MAC_DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA_MAC) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify || xcodebuild build \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(MAC_DESTINATION) \
			-configuration Release \
			-derivedDataPath $(DERIVED_DATA_MAC) \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			CODE_SIGN_IDENTITY="-" \
			CODE_SIGNING_REQUIRED=NO \
			CODE_SIGNING_ALLOWED=NO
	@echo "$(GREEN)macOS build complete$(NC)"

#------------------------------------------------------------------------------
# Build for iOS (iPhone)
#------------------------------------------------------------------------------
build-ios: build-ipad

#------------------------------------------------------------------------------
# Build for iPadOS (iPad)
#------------------------------------------------------------------------------
build-ipad: check-tools
	@echo "$(YELLOW)Building for iPadOS (iPad)...$(NC)"
	@if [ -z "$(IPAD_SIMULATOR_ID)" ] && [ -z "$(IPAD_SIMULATOR_NAME)" ]; then \
		echo "$(RED)Error: No available iPad simulator found. Install an iPad simulator in Xcode > Settings > Platforms.$(NC)"; \
		exit 1; \
	fi
	@mkdir -p $(BUILD_DIR)/ipad
	@set -o pipefail; \
	xcodebuild build \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(IPAD_DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA_IPAD) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify || xcodebuild build \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(IPAD_DESTINATION) \
			-configuration Release \
			-derivedDataPath $(DERIVED_DATA_IPAD) \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			CODE_SIGN_IDENTITY="-" \
			CODE_SIGNING_REQUIRED=NO \
			CODE_SIGNING_ALLOWED=NO
	@echo "$(GREEN)iPadOS (iPad) build complete$(NC)"

#------------------------------------------------------------------------------
# Build All Platforms
#------------------------------------------------------------------------------
build-all: build-mac build-ios build-ipad
	@echo "$(GREEN)All platform builds complete$(NC)"

build: build-mac

#------------------------------------------------------------------------------
# Deploy to macOS
#------------------------------------------------------------------------------
deploy-mac: build-mac
	@echo "$(YELLOW)Deploying to macOS...$(NC)"
	@killall qw 2>/dev/null || true
	@APP_PATH=$$(find $(DERIVED_DATA_MAC) -name "$(PROJECT_NAME).app" -path "*/Release/*" | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		open "$$APP_PATH"; \
		echo "$(GREEN)App launched: $$APP_PATH$(NC)"; \
	else \
		echo "$(RED)Error: Could not find built app$(NC)"; \
		exit 1; \
	fi

#------------------------------------------------------------------------------
# Deploy to iPhone Simulator
#------------------------------------------------------------------------------
deploy-ios: deploy-ipad

#------------------------------------------------------------------------------
# Deploy to iPad Simulator
#------------------------------------------------------------------------------
deploy-ipad: build-ipad
	@echo "$(YELLOW)Deploying to iPad Simulator...$(NC)"
	@if [ -z "$(IPAD_SIMULATOR_ID)" ] && [ -z "$(IPAD_SIMULATOR_NAME)" ]; then \
		echo "$(RED)Error: No available iPad simulator found. Install an iPad simulator in Xcode > Settings > Platforms.$(NC)"; \
		exit 1; \
	fi
	@if [ -n "$(IPAD_SIMULATOR_ID)" ]; then \
		xcrun simctl boot "$(IPAD_SIMULATOR_ID)" 2>/dev/null || true; \
	else \
		xcrun simctl boot "$(IPAD_SIMULATOR_NAME)" 2>/dev/null || true; \
	fi
	@open -a Simulator
	@APP_PATH=$$(find $(DERIVED_DATA_IPAD) -name "$(PROJECT_NAME).app" -path "*iphonesimulator*" | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		xcrun simctl install booted "$$APP_PATH" && \
		xcrun simctl launch booted muonium.qw && \
		echo "$(GREEN)App deployed to iPad Simulator$(NC)"; \
	else \
		echo "$(RED)Error: Could not find iPad app$(NC)"; \
		exit 1; \
	fi

#------------------------------------------------------------------------------
# Deploy to All Platforms
#------------------------------------------------------------------------------
deploy: deploy-mac

#------------------------------------------------------------------------------
# Run (alias for deploy-mac)
#------------------------------------------------------------------------------
run: deploy-mac

#------------------------------------------------------------------------------
# Run on iPhone/iPad Simulator
#------------------------------------------------------------------------------
run-ios: run-ipad

run-ipad: deploy-ipad

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------
test: check-tools
	@echo "$(YELLOW)Running tests...$(NC)"
	@set -o pipefail; \
	xcodebuild test \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(MAC_DESTINATION) \
		-derivedDataPath $(DERIVED_DATA_MAC) \
		| xcbeautify || xcodebuild test \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(MAC_DESTINATION) \
			-derivedDataPath $(DERIVED_DATA_MAC)
	@echo "$(GREEN)Tests complete$(NC)"

#------------------------------------------------------------------------------
# Archive for Distribution
#------------------------------------------------------------------------------
archive-mac: check-tools
	@echo "$(YELLOW)Creating macOS archive...$(NC)"
	@mkdir -p $(BUILD_DIR)/archives
	xcodebuild archive \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(MAC_DESTINATION) \
		-archivePath $(BUILD_DIR)/archives/$(PROJECT_NAME)-macOS.xcarchive \
		DEVELOPMENT_TEAM=$(TEAM_ID)
	@echo "$(GREEN)macOS archive created$(NC)"

#------------------------------------------------------------------------------
# Export for App Store
#------------------------------------------------------------------------------
export-mac: archive-mac
	@echo "$(YELLOW)Exporting for App Store...$(NC)"
	@mkdir -p $(BUILD_DIR)/export
	xcodebuild -exportArchive \
		-archivePath $(BUILD_DIR)/archives/$(PROJECT_NAME)-macOS.xcarchive \
		-exportPath $(BUILD_DIR)/export \
		-exportOptionsPlist ExportOptions.plist
	@echo "$(GREEN)App exported to $(BUILD_DIR)/export$(NC)"

#------------------------------------------------------------------------------
# Install App and CLI
#------------------------------------------------------------------------------
install: build-mac install-cli
	@echo "$(YELLOW)Installing QW Editor to /Applications...$(NC)"
	@if [ -d "/Applications/qw.app" ]; then \
		rm -rf "/Applications/qw.app"; \
	fi
	@cp -R "$(DERIVED_DATA_MAC)/Build/Products/Release/qw.app" "/Applications/"
	@echo "$(GREEN)QW Editor installed to /Applications/qw.app$(NC)"
	@echo "$(GREEN)You can now use 'qw' command from terminal$(NC)"

#------------------------------------------------------------------------------
# Install CLI Only
#------------------------------------------------------------------------------
install-cli:
	@echo "$(YELLOW)Installing 'qw' command line tool...$(NC)"
	@mkdir -p /usr/local/bin
	@cp cli/qw /usr/local/bin/qw
	@chmod +x /usr/local/bin/qw
	@echo "$(GREEN)CLI installed to /usr/local/bin/qw$(NC)"
	@echo ""
	@echo "Usage:"
	@echo "  qw                 - Open QW Editor"
	@echo "  qw file.txt        - Open a file"
	@echo "  qw .               - Open current folder"
	@echo "  qw -h              - Show help"

#------------------------------------------------------------------------------
# Uninstall
#------------------------------------------------------------------------------
uninstall:
	@echo "$(YELLOW)Uninstalling QW Editor...$(NC)"
	@if [ -d "/Applications/qw.app" ]; then \
		rm -rf "/Applications/qw.app"; \
		echo "$(GREEN)Removed /Applications/qw.app$(NC)"; \
	fi
	@if [ -f "/usr/local/bin/qw" ]; then \
		rm -f "/usr/local/bin/qw"; \
		echo "$(GREEN)Removed /usr/local/bin/qw$(NC)"; \
	fi
	@echo "$(GREEN)Uninstall complete$(NC)"
