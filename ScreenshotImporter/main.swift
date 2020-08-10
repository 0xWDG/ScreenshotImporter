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
/// Desktop Path
let desktopPath = (
    NSSearchPathForDirectoriesInDomains(
        .desktopDirectory,
        .userDomainMask,
        true
    ) as [String]
).first!

/// Library path
let libraryPath = (
    NSSearchPathForDirectoriesInDomains(
        .libraryDirectory,
        .userDomainMask,
        true
    ) as [String]
).first!

/// Program arguments
let arguments = CommandLine.arguments

/// Executable path
let executablePath = Bundle.main.bundlePath

/// Executable path (URL)
let executableURL = Bundle.main.bundleURL.appendingPathComponent("ScreenshotImporter")

/// Settings.json URL String
let settingsURLString = "\(executablePath)/Settings.json"

/// Settings.json URL
let settingsURL = URL(string: "file://\(settingsURLString)")!

/// Deamon path
let deamonPath = "\(libraryPath)/LaunchAgents/com.wdgwv.ScreenshotImporter.plist"

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
    debug: false,
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

@discardableResult
func shell(_ command: String) -> (output: String, error: String) {
    if Settings.debug {
        print("Running command '\(command)'")
    }
    let task = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    
    task.standardOutput = outputPipe
    task.standardError = errorPipe
    
    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"
    task.launch()
    
    let output = String(
        data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    )!
    
    let error = String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    )!
    
    if Settings.debug {
        if !output.isEmpty {
            print("Return value: \(output)")
        }
        #if DEBUG
        if !error.isEmpty {
            print("Error value: \(error)")
        }
        #endif
    }
    
    return (output, error)
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
            
            if Settings.debug {
                print("Loaded settigs from \(settingsURLString)")
            }
        }
        catch {
            dialog(
                notificationType: .notice,
                title: "ScreenshotImporter",
                message: "Could not parse \"settings.json\", using default settings"
            )
        }
    } else {
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
                    try jsonData.write(
                        to: URL(
                            string: "file://\(Settings.checkPath)/Settings.json"
                        )!
                    )
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
        PHPhotoLibrary.requestAuthorization { (status) in
            if Settings.debug {
                print("Status: \(status.rawValue)")
            }
        }
        
    case .denied:
        if Settings.debug {
            print(".denied")
        }
        PHPhotoLibrary.requestAuthorization { (status) in
            if Settings.debug {
                print("Status: \(status.rawValue)")
            }
        }
        
    case .authorized:
        if Settings.debug {
            print(".authorized")
        }
        
    @unknown default:
        if Settings.debug {
            print("Unexpected permission.")
        }
        PHPhotoLibrary.requestAuthorization { (status) in
            if Settings.debug {
                print("Status: \(status.rawValue)")
            }
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

func installScreenshotImporter() {
    if !FileManager.default.fileExists(atPath: "\(Settings.checkPath)/ScreenshotImporter") {
        do {
            try FileManager.default.copyItem(
                at: executableURL,
                to: URL(string: "file://\(Settings.checkPath)/ScreenshotImporter")!
            )
        }
        catch {
            print("Failed to copy")
            print("From: \(executableURL.absoluteString)")
            print("To: \(URL(string: "\(Settings.checkPath)/ScreenshotImporter")!.absoluteString)")
        }
        
    }
    shell("chmod +x \"\(Settings.checkPath)/ScreenshotImporter\"")
}

func installLaunchDeamon() {
    if !FileManager.default.fileExists(atPath: deamonPath) {
        // We cannot run this file direclty because the Photos.app permissions which are needed.
        let newPlist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n"
            + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\r\n"
            + "<plist version=\"1.0\">\r\n"
            + "  <dict>\r\n"
            + "     <key>Label</key>\r\n"
            + "     <string>com.wdgwv.ScreenshotImporter</string>\r\n"
            + "     <key>ProgramArguments</key>\r\n"
            + "     <array>\r\n"
            + "         <string>/usr/bin/open</string>"
            + "         <string>-F</string>"
            + "         <string>-j</string>"
            + "         <string>-g</string>"
            + "         <string>\(Settings.checkPath)/ScreenshotImporter</string>\r\n"
            + "     </array>\r\n"
            + "     <key>RunAtLoad</key>\r\n"
            + "     <true />\r\n"
            + "     <key>StartInterval</key>\r\n"
            + "     <integer>30</integer>\r\n"
            + "     <key>StandardErrorPath</key>\r\n"
            + "     <string>\(Settings.checkPath)/Error.txt</string>\r\n"
            + "     <key>StandardOutPath</key>\r\n"
            + "     <string>\(Settings.checkPath)/Stdout.txt</string>\r\n"
            + "  </dict>\r\n"
            + "</plist>"
        
        do {
            try newPlist.data(using: .utf8)?.write(
                to: URL(string: "file://\(deamonPath)")!
            )
        }
        catch {
            dialog(
                notificationType: .fatalError,
                title: "ScreenshotImporter",
                message: "Could not write launch deamon\nURL: \(deamonPath)\nError: \(error.localizedDescription)"
            )
        }
    }
    
    // Run command to register
    shell("chmod 600 \"\(deamonPath)\"")
    shell("launchctl load \"\(deamonPath)\"")
    shell("launchctl start \"\(deamonPath)\"")
    shell("defaults write com.apple.screencapture location ~/Desktop/Screenshots")
}

// MARK: - Create directory
func createDirectoryIfNeeded() {
    if !FileManager.default.fileExists(atPath: Settings.checkPath) {
        do {
            try FileManager.default.createDirectory(
                atPath: Settings.checkPath,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.extensionHidden: true]
            )
        }
        catch {
            dialog(
                notificationType: .fatalError,
                title: "ScreenshotImporter",
                message: "Cannot create directory at \"\(Settings.checkPath)\" please create the directory"
            )
            
            exit(4)
        }
    } else {
        try? FileManager.default.setAttributes(
            [FileAttributeKey.extensionHidden: true],
            ofItemAtPath: Settings.checkPath
        )
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
        #if DEBUG
        if Settings.debug {
            print("file: \(item.lastPathComponent) = \(item.pathExtension), \(Settings.allowedExtensions.contains(item.pathExtension) ? "Import" : "Ignore")")
        }
        #endif
        
        if Settings.allowedExtensions.contains(item.pathExtension) {
            importFile(atURL: item)
        }
    }
}

// MARK: - Edit EXIF to "Screenshot"
func updateEXIF(inputImageData: Data) -> Data {
    let ImagePropertyExifDictionary = kCGImagePropertyExifDictionary as String
    
    // Read source and get properties
    guard let sourceRef = CGImageSourceCreateWithData(inputImageData as CFData, nil) else {
        return inputImageData
    }
    
    guard var metadata = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [String: Any] else {
        return inputImageData
    }
    
    // Modify EXIF Screenshot property
    guard var exif = metadata[ImagePropertyExifDictionary] as? [String: Any] else {
        return inputImageData
    }
    
    exif[kCGImagePropertyExifUserComment as String] = "Screenshot"
    metadata[ImagePropertyExifDictionary] = exif as CFDictionary
    
    // Set up destination
    let dData: CFMutableData = NSMutableData()
    
    guard let destinationRef = CGImageDestinationCreateWithData(dData, kUTTypePNG, 1, nil) else {
        return inputImageData
    }
    
    // Add image from source to destination with new properties
    CGImageDestinationAddImageFromSource(destinationRef, sourceRef, 0, metadata as CFDictionary)
    
    // Save destination
    guard CGImageDestinationFinalize(destinationRef) else {
        return inputImageData
    }
    
    return dData as Data
}

// MARK: - Import the photo

/// Import photo to Photos.app
/// - Parameter atURL: the photo URL
func importFile(atURL: URL) {
    image = nil
    
    do {
        let imageData: Data = try .init(
            contentsOf: atURL,
            options: .mappedIfSafe
        )
        
        // Update EXIF Image data.
        var updatedImageData = imageData
        
        if Settings.addScreenshotEXIF {
            // Add the missing EXIF data.
            updatedImageData = updateEXIF(inputImageData: imageData)
        }
        
        image = NSImage(data: updatedImageData)!
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
            dialog(
                notificationType: .fatalError,
                title: "ScreenshotImporter",
                message: "There is no asset collection available, cannot continue."
            )
            
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
    createDirectoryIfNeeded()
}.then {
    installScreenshotImporter()
}.then {
    installLaunchDeamon()
}.then {
    readDirectory()
}
