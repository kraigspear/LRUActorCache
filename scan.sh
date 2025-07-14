#!/bin/bash
# Build LRUActorCache package and run periphery scan

# Build for macOS (simpler and more reliable for a library)
xcodebuild -scheme LRUActorCache \
  -destination 'platform=macOS' \
  -derivedDataPath './DerivedData' \
  clean build

# Run periphery scan on the built index
periphery scan \
  --skip-build \
  --index-store-path './DerivedData/Index.noindex/DataStore/' \
  --report-include "Sources/**/*.swift" \
  --retain-public