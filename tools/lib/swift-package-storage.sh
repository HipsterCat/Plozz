#!/usr/bin/env bash

# Configure Xcode's SwiftPM storage without sharing mutable checkout state
# between independent writers. The compressed repository/artifact cache is safe
# to reuse; checkouts and artifact extraction remain private to the caller.
configure_plozz_package_resolution() {
  if [[ "$#" -ne 1 || -z "$1" ]]; then
    echo "configure_plozz_package_resolution: expected a writer-specific checkout path" >&2
    return 2
  fi

  local cloned_source_packages="$1"
  local package_cache="${PLOZZ_PACKAGE_CACHE_PATH:-$HOME/Library/Caches/org.swift.swiftpm}"
  PACKAGE_RESOLUTION_ARGS=(
    -clonedSourcePackagesDirPath "$cloned_source_packages"
    -packageCachePath "$package_cache"
    -onlyUsePackageVersionsFromResolvedFile
    -skipPackageUpdates
  )
}
