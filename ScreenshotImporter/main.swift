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
    var addScreenshotEXIF: Bool
    var albumName: String
    var allowedExtensions: [String]
    var checkPath: String
    var debug: Bool
    var deleteAfterImport: Bool
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
    addScreenshotEXIF: true,
    albumName: "Screenshots",
    allowedExtensions: [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "tiff",
        "bmp",
        "pdf"
    ],
    checkPath: desktopPath + "/Screenshots",
    debug: true,
    deleteAfterImport: true
)

/// Can the program exit already?
var programCanExit = false

/// What is the file list
var fileList: [URL]?

/// Current image
var image: NSImage?

/// Current asset collection
var assetCollection: PHAssetCollection!

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
            
            if Settings.debug {
                let jsonString = String(data: jsonData, encoding: .utf8)!
                print(jsonString)
            }
            
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
        if Settings.debug {
            print(".notDetermined")
        }
        PHPhotoLibrary.requestAuthorization { (status) in
            if Settings.debug {
                print("Status: \(status.rawValue)")
            }
        }
        
    case .restricted:
        if Settings.debug {
            print(".restricted")
        }
        
    case .denied:
        if Settings.debug {
            print(".denied")
        }
        
    case .authorized:
        if Settings.debug {
            print(".authorized")
        }
        
    @unknown default:
        if Settings.debug {
            print("Unexpected permission.")
        }
    }
}


func createAlbumIfNeeded() {
    if let unwrappedAssetCollection = fetchAssetCollectionForAlbum() {
        // Album already exists
        assetCollection = unwrappedAssetCollection
        return
    }
    
    PHPhotoLibrary.shared().performChanges({
        if Settings.debug {
            print("Creating album request...")
        }
        
        PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
            withTitle: Settings.albumName
        )
    }) { success, error in
        if Settings.debug {
            print("There sould be a return value...")
        }
        
        if success {
            if Settings.debug {
                print("The album should be created...")
            }
            
            assetCollection = fetchAssetCollectionForAlbum()
            
        } else {
            if Settings.debug {
                print("Error \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    if Settings.debug {
        print("Finished album request...")
    }
}

func fetchAssetCollectionForAlbum() -> PHAssetCollection? {
    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = NSPredicate(
        format: "title = %@",
        Settings.albumName
    )
    
    let collection = PHAssetCollection.fetchAssetCollections(
        with: .album,
        subtype: .any,
        options: fetchOptions
    )
    
    if let _: AnyObject = collection.firstObject {
        return collection.firstObject
    }
    
    return nil
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

// MARK: - Import the photo
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
        guard let assetCollection = assetCollection else {
            dialog(notificationType: .fatalError, title: "screenshotImporter", message: "There is no asset collection available, cannot continue.")
            return
        }
        let assetChangeRequest = PHAssetChangeRequest.creationRequestForAsset(
            from: image
        )
        
        let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
        
        let albumChangeRequest = PHAssetCollectionChangeRequest(
            for: assetCollection
        )
        
        let enumeration: NSArray = [assetPlaceHolder!]
        
        albumChangeRequest!.addAssets(enumeration)
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
    createAlbumIfNeeded()
}.then {
    readDirectory()
}
