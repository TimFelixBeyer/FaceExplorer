//
//  AppDelegate.swift
//  FaceExplorer
//
//  Created by Tim Beyer on 01.03.23.
//  Copyright © 2023 Apple. All rights reserved.
//
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
