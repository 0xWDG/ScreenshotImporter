//
//  main.swift
//  ScreenshotImporter
//
//  Created by Wesley de Groot on 01/08/2020.
//  Copyright © 2020 Wesley de Groot. All rights reserved.
//

import Foundation
import Photos
import AppKit

/// <#Description#>
public class Run {
    typealias Action = () -> Void
    /// <#Description#>
    var queue: [Action] = [Action]()
    
    /// <#Description#>
    /// - Parameter act: <#act description#>
    init(act: @escaping Action) {
        queue.append(act)
    }
    
    /// <#Description#>
    /// - Parameter act: <#act description#>
    /// - Returns: <#description#>
    @discardableResult
    func then(act: @escaping Action) -> Self {
        queue.append(act)
        return self
    }
    
    /// <#Description#>
    deinit {
        for item in queue {
            item()
        }
    }
}
print("Loading...")

// MARK: - Settings JSON Codable
struct SettingsJSON: Codable {
    var checkPath: String
    var deleteAfterImport: Bool
    var allowedExtensions: [String]
}

// MARK: - Variables
/// Program arguments
let arguments = CommandLine.arguments

/// Executable path
let executablePath = Bundle.main.bundlePath

/// Info.plist URL String
let infoPlistURLString = "\(executablePath)/Info.plist"


/// Settings.json URL String
let settingsURLString = "file://\(executablePath)/Settings.json"

/// Settings.json URL
let settingsURL = URL(string: settingsURLString)!

/// Desktop Path
let desktopPath = (
    NSSearchPathForDirectoriesInDomains(
        .desktopDirectory,
        .userDomainMask,
        true
        ) as [String]
    ).first!

/// Settings of the application
var Settings: SettingsJSON = SettingsJSON.init(
    checkPath: desktopPath + "/screenshots",
    deleteAfterImport: true,
    allowedExtensions: [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "tiff",
        "bmp",
        "pdf"
    ]
)

/// Can the program exit already?
var programCanExit = false

/// What is the file list
var fileList: [URL]?

/// Current image
var image: NSImage?

// MARK: - Alert box

/// Which notification types are available
enum notificationType {
    case fatalError
    case warning
    case question, note, notice
    case appicon, `default`
}


/// Display a dialog box
/// - Parameters:
///   - notificationType: Notification type see `notificationType`
///   - title: dialog box title
///   - message: dialog box message
/// - Returns: true if clicked on ok, false if clicked on cancel
@discardableResult func dialog(notificationType: notificationType, title: String, message: String) -> Bool {
    var cancelButton: Bool = true
    var kCFUserNotificationLevel: CFOptionFlags
    
    switch notificationType {
    case .fatalError:
        kCFUserNotificationLevel = kCFUserNotificationStopAlertLevel
        cancelButton = false
        
    case .warning:
        kCFUserNotificationLevel = kCFUserNotificationCautionAlertLevel
        cancelButton = false
        
    case .question:
        kCFUserNotificationLevel = kCFUserNotificationNoteAlertLevel
        
    case .note, .notice:
        kCFUserNotificationLevel = kCFUserNotificationNoteAlertLevel
        cancelButton = false
        
    default:
        kCFUserNotificationLevel = kCFUserNotificationPlainAlertLevel
    }
    
    /// What are the response flags?
    var responseFlags: CFOptionFlags = 0
    
    // Create the user notification
    CFUserNotificationDisplayAlert(
        // timeout
        0,
        
        // flags
        kCFUserNotificationLevel,
        
        // icon URL
        nil,
        
        // sound URL
        nil,
        
        // localization URL
        nil,
        
        // Title
        title as CFString,
        
        // Message
        message as CFString,
        
        // Primary button
        "Ok" as CFString,
        
        // Secondary button
        cancelButton ? "Cancel" as CFString : nil,
        
        // 3th button
        nil,
        
        // Response pointer
        &responseFlags
    )
    
    // 0 = Ok
    return responseFlags == 0
}

// MARK: - Read settings
func readSettings() {
    if FileManager.default.fileExists(atPath: settingsURLString) {
        // Try to decode.
        do {
            let jsonData = try Data(contentsOf: settingsURL)
            
            Settings = try JSONDecoder().decode(
                SettingsJSON.self,
                from: jsonData
            )
        }
        catch {
            dialog(
                notificationType: .notice,
                title: "ScreenshotImporter",
                message: "Could not parse \"settings.json\", using default settings"
            )
        }
    }
    
    do {
        let question = dialog(
            notificationType: .question,
            title: "ScreenshotImporter",
            message: "Do you want to generate a \"settings.json\", using default settings, so that you can customize it?"
        )
        
        if question {
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = .prettyPrinted
            let jsonData = try jsonEncoder.encode(Settings)
            #if DEBUG
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print(jsonString)
            #endif
            do {
                try jsonData.write(to: settingsURL)
            }
            catch {
                dialog(
                    notificationType: .notice,
                    title: "ScreenshotImporter",
                    message: "Failed to write default settings\n\(error.localizedDescription)"
                )
            }
        }
    }
    catch {
        print(error)
    }
}

// MARK: - Check permissions
func gotPermission() {
    switch PHPhotoLibrary.authorizationStatus() {
    case .notDetermined:
        print(".notDetermined")
        PHPhotoLibrary.requestAuthorization { (status) in
            print("Status: \(status.rawValue)")
        }
        
    case .restricted:
        print(".restricted")
        
    case .denied:
        print(".denied")
        
    case .authorized:
        print(".authorized")
        
    @unknown default:
        print("?")
    }
}

// MARK: - Read directory
func readDirectory() {
    fileList = try? FileManager.default.contentsOfDirectory(
        at: URL.init(string: Settings.checkPath)!,
        includingPropertiesForKeys: nil,
        options: FileManager.DirectoryEnumerationOptions.producesRelativePathURLs
    )
    
    guard let fileList = fileList else {
        dialog(
            notificationType: .notice,
            title: "ScreenshotImporter",
            message: "Could not read directory...."
        )
        exit(2)
    }
    
    for item in fileList {
        print("file: \(item.lastPathComponent) = \(item.pathExtension), \(Settings.allowedExtensions.contains(item.pathExtension) ? "Import" : "Ignore")")
        
        if Settings.allowedExtensions.contains(item.pathExtension) {
            importFile(atURL: item)
        }
    }
    print(fileList)
}

func importFile(atURL: URL) {
    image = nil
    
    do {
        let imageData: Data = try .init(
            contentsOf: atURL,
            options: .mappedIfSafe
        )
        
        image = NSImage(data: imageData)!
    }
    catch {
        dialog(
            notificationType: .notice,
            title: "ScreenshotImporter",
            message: "Something went wrong with \"\(atURL.absoluteString)\".\n\(error.localizedDescription)"
        )
        return
    }
    
    guard let image = image else {
        dialog(
            notificationType: .notice,
            title: "ScreenshotImporter",
            message: "Failed to unwrap image(URL: \"\(atURL.absoluteString)), this should never happen..."
        )
        return
    }
    
    
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
    }) { (suceed, error) in
        if let error = error {
            dialog(
                notificationType: .notice,
                title: "ScreenshotImporter",
                message: "There was a error importing \"\(atURL.absoluteString)\"\nError: \(error)"
            )
            return
        }
        
        if suceed {
            // Delete that image
            print("The image \"\(atURL.absoluteString)\" should be saved")
            
            if Settings.deleteAfterImport {
                do {
                    try FileManager.default.removeItem(at: atURL)
                }
                catch {
                    dialog(
                        notificationType: .notice,
                        title: "ScreenshotImporter",
                        message: "Failed to delete \"\(atURL.absoluteString)\"."
                    )
                }
            }
        } else {
            // Something unexpected went wrong
            dialog(
                notificationType: .notice,
                title: "ScreenshotImporter",
                message: "Something unexpected went wrong with image \"\(atURL.absoluteString)\"."
            )
        }
        
        programCanExit = true
    }
    
    while !programCanExit {
        // Sleep...
    }
}

Run {
    readSettings()
}.then {
    gotPermission()
}.then {
    readDirectory()
}
