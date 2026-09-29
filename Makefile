.PHONY: build test run demo clean

build:
	mkdir -p .build
	cd backend && go build -trimpath -o ../.build/pipelines-helper .
	swift build -c release
	swift packaging/generate-icon.swift .build/Pipelines.iconset
	iconutil -c icns .build/Pipelines.iconset -o .build/Pipelines.icns
	mkdir -p dist/Pipelines.app/Contents/MacOS dist/Pipelines.app/Contents/Resources
	cp .build/release/Pipelines dist/Pipelines.app/Contents/MacOS/Pipelines
	cp .build/pipelines-helper dist/Pipelines.app/Contents/MacOS/pipelines-helper
	cp packaging/Info.plist dist/Pipelines.app/Contents/Info.plist
	cp .build/Pipelines.icns dist/Pipelines.app/Contents/Resources/Pipelines.icns
	codesign --force --deep --sign - dist/Pipelines.app

test:
	cd backend && go test ./...
	swift test

run: build
	open dist/Pipelines.app

demo: build
	open -n dist/Pipelines.app --args --demo

clean:
	swift package clean
