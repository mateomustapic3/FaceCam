#!/bin/bash
# Pokreni u istom folderu gdje su main.swift i Info.plist:  bash build.sh
set -e
APP="FaceCam.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -o "$APP/Contents/MacOS/FaceCam" main.swift
codesign --force --sign - "$APP"
echo "Gotovo. Pokreni s:  open $APP"
