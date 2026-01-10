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
DERIVED_DATA := $(BUILD_DIR)/DerivedData

# Deployment targets
MACOS_DEPLOYMENT_TARGET := 15.0
IOS_DEPLOYMENT_TARGET := 18.0

# App icon source
ICON_SOURCE := requirements/qw_logo.png
ICON_DIR := $(PROJECT_DIR)/$(PROJECT_NAME)/Assets.xcassets/AppIcon.appiconset

# Simulator destinations
MAC_DESTINATION := "platform=macOS"
IPHONE_DESTINATION := "platform=iOS Simulator,name=iPhone 17"
IPAD_DESTINATION := "platform=iOS Simulator,name=iPad Pro 13-inch (M4)"

# Device destinations (for actual devices)
IPHONE_DEVICE := "platform=iOS,name=iPhone"
IPAD_DEVICE := "platform=iOS,name=iPad"

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: all clean build build-mac build-ios build-ipad build-all \
        deploy deploy-mac deploy-ios deploy-ipad \
        test run icons help check-tools

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
	@echo "  make build-ios    - Build for iOS (iPhone & iPad)"
	@echo "  make build-ipad   - Build for iPad only"
	@echo "  make build-all    - Build for all platforms"
	@echo ""
	@echo "$(YELLOW)Deploy Targets:$(NC)"
	@echo "  make deploy-mac   - Build and run on macOS"
	@echo "  make deploy-ios   - Build and deploy to iPhone Simulator"
	@echo "  make deploy-ipad  - Build and deploy to iPad Simulator"
	@echo "  make deploy       - Deploy to all platforms"
	@echo ""
	@echo "$(YELLOW)Other Targets:$(NC)"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make test         - Run unit tests"
	@echo "  make run          - Build and run on macOS"
	@echo "  make icons        - Generate app icons from qw_logo.png"
	@echo "  make check-tools  - Verify required tools are installed"
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
# Clean
#------------------------------------------------------------------------------
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(PROJECT_NAME)-*
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
	xcodebuild build \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(MAC_DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify || xcodebuild build \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(MAC_DESTINATION) \
			-configuration Release \
			-derivedDataPath $(DERIVED_DATA) \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			CODE_SIGN_IDENTITY="-" \
			CODE_SIGNING_REQUIRED=NO \
			CODE_SIGNING_ALLOWED=NO
	@echo "$(GREEN)macOS build complete$(NC)"

#------------------------------------------------------------------------------
# Build for iOS (iPhone)
#------------------------------------------------------------------------------
build-ios: check-tools
	@echo "$(YELLOW)Building for iOS (iPhone)...$(NC)"
	@mkdir -p $(BUILD_DIR)/ios
	xcodebuild build \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(IPHONE_DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify || xcodebuild build \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(IPHONE_DESTINATION) \
			-configuration Release \
			-derivedDataPath $(DERIVED_DATA) \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			CODE_SIGN_IDENTITY="-" \
			CODE_SIGNING_REQUIRED=NO \
			CODE_SIGNING_ALLOWED=NO
	@echo "$(GREEN)iOS (iPhone) build complete$(NC)"

#------------------------------------------------------------------------------
# Build for iPadOS (iPad)
#------------------------------------------------------------------------------
build-ipad: check-tools
	@echo "$(YELLOW)Building for iPadOS (iPad)...$(NC)"
	@mkdir -p $(BUILD_DIR)/ipad
	xcodebuild build \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(IPAD_DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify || xcodebuild build \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(IPAD_DESTINATION) \
			-configuration Release \
			-derivedDataPath $(DERIVED_DATA) \
			DEVELOPMENT_TEAM=$(TEAM_ID) \
			CODE_SIGN_IDENTITY="-" \
			CODE_SIGNING_REQUIRED=NO \
			CODE_SIGNING_ALLOWED=NO
	@echo "$(GREEN)iPadOS (iPad) build complete$(NC)"

#------------------------------------------------------------------------------
# Build All Platforms
#------------------------------------------------------------------------------
build-all: build-mac build-ios
	@echo "$(GREEN)All platform builds complete$(NC)"

build: build-mac

#------------------------------------------------------------------------------
# Deploy to macOS
#------------------------------------------------------------------------------
deploy-mac: build-mac
	@echo "$(YELLOW)Deploying to macOS...$(NC)"
	@APP_PATH=$$(find $(DERIVED_DATA) -name "$(PROJECT_NAME).app" -path "*/Release/*" | head -1) && \
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
deploy-ios: build-ios
	@echo "$(YELLOW)Deploying to iPhone Simulator...$(NC)"
	@xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
	@open -a Simulator
	@APP_PATH=$$(find $(DERIVED_DATA) -name "$(PROJECT_NAME).app" -path "*iphonesimulator*" | head -1) && \
	if [ -n "$$APP_PATH" ]; then \
		xcrun simctl install booted "$$APP_PATH" && \
		xcrun simctl launch booted muonium.qw && \
		echo "$(GREEN)App deployed to iPhone Simulator$(NC)"; \
	else \
		echo "$(RED)Error: Could not find iOS app$(NC)"; \
		exit 1; \
	fi

#------------------------------------------------------------------------------
# Deploy to iPad Simulator
#------------------------------------------------------------------------------
deploy-ipad: build-ipad
	@echo "$(YELLOW)Deploying to iPad Simulator...$(NC)"
	@xcrun simctl boot "iPad Pro 13-inch (M4)" 2>/dev/null || true
	@open -a Simulator
	@APP_PATH=$$(find $(DERIVED_DATA) -name "$(PROJECT_NAME).app" -path "*iphonesimulator*" | head -1) && \
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
# Run Tests
#------------------------------------------------------------------------------
test: check-tools
	@echo "$(YELLOW)Running tests...$(NC)"
	xcodebuild test \
		-project $(XCODEPROJ) \
		-scheme $(SCHEME) \
		-destination $(MAC_DESTINATION) \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify || xcodebuild test \
			-project $(XCODEPROJ) \
			-scheme $(SCHEME) \
			-destination $(MAC_DESTINATION) \
			-derivedDataPath $(DERIVED_DATA)
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
