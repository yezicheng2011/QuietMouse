# Quiet Mouse

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/yezicheng2011/QuietMouse)](https://github.com/yezicheng2011/QuietMouse/releases)

<p align="center">
  <img src="Icon/Logo-Light.png" width="160" alt="Quiet Mouse">
</p>

Quiet Mouse adds tap-to-click to the Apple Magic Mouse on macOS. A light tap is enough — you don't have to press the mouse down — so clicks stay quiet. Scrolling and gestures are unchanged.

Website: https://quietmouse.org
Personal home: https://danielye2011.uk

## Features

- A **tap on the left half** of the mouse surface is a left click, and a **tap on the right half** is a right click. The split follows the left/right button setting in **System Settings → Mouse**. If the system is set to one button, every tap is a left click.
- **You do not press the mouse down**, so there is almost no click sound.
- **Scrolling and swipe gestures are unchanged.** Two fingers cancel the tap, which avoids an accidental click.
- The physical press still works. A tap that lands at the same moment as a physical press is ignored, so it does not click twice.
- A menu-bar icon turns tap-to-click on or off, sets the app to open at login, and jumps to the permission settings.
- Requires **macOS 13** or later, and a Magic Mouse with a multi-touch surface.

## Install

Download `QuietMouse-<version>-macos.zip` from [Releases](https://github.com/yezicheng2011/QuietMouse/releases), unzip it, and drag `QuietMouse.app` into Applications.

The app is ad-hoc signed and is not notarized by Apple. The first time you open it:

1. Do not only double-click. Control-click the app and choose **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway**.
2. When prompted, allow **Accessibility** and **Input Monitoring**. If the menu bar still shows a missing permission, click **Grant Permissions…** to open the matching settings page.
3. Connect the Magic Mouse over Bluetooth. A mouse icon in the menu bar means the app is running.

Put the app in the Applications folder before you turn on **Open at Login**.

## Build from source

Requires macOS 13 or later, and the Xcode Command Line Tools (`swiftc`).

```bash
./build.sh
```

This writes a signed `QuietMouse.app` in the current directory. To debug:

```bash
QuietMouse.app/Contents/MacOS/QuietMouse --debug
QuietMouse.app/Contents/MacOS/QuietMouse --list
```

Regenerate the icons:

```bash
swift Icon/make-icons.swift Icon
iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
```

## How it works

The app watches contact points on the Magic Mouse surface. A short, almost motionless one-finger tap becomes one mouse click. More than one finger, a swipe, pointer movement, or holding too long does not trigger a click. Scroll gestures themselves are not intercepted.

## License

Apache License 2.0. Copyright 2026 Ye Zicheng.
