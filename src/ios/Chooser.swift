import UIKit
import MobileCoreServices
import Foundation

@objc(Chooser)
class Chooser : CDVPlugin {
	var commandCallback: String?
    // Define a structure to hold file information
    struct FileInfo: Codable {
        let mediaType: String
        let name: String
        let uri: String
     }

	// Function to call the document picker with specified UTIs and multiple selection option
    func callPicker (utis: [String], allowMultipleSelection: Bool) {
		let picker = UIDocumentPickerViewController(documentTypes: utis, in: .import)
		picker.delegate = self
		// Set the allowsMultipleSelection property based on the passed parameter
        if #available(iOS 11.0, *) {
            picker.allowsMultipleSelection = allowMultipleSelection
        }

		self.viewController.present(picker, animated: true, completion: nil)
	}

	func detectMimeType (_ url: URL) -> String {
		if let uti = UTTypeCreatePreferredIdentifierForTag(
			kUTTagClassFilenameExtension,
			url.pathExtension as CFString,
			nil
		)?.takeRetainedValue() {
			if let mimetype = UTTypeCopyPreferredTagWithClass(
				uti,
				kUTTagClassMIMEType
			)?.takeRetainedValue() as? String {
				return mimetype
			}
		}

		return "application/octet-stream"
	}
    
	// Moves the file to tmp directory whose contents can be purged by OS when app is inactive
	func moveFileToTMP(at srcURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destDirectory = NSTemporaryDirectory()
        
        let originalName = srcURL.deletingPathExtension().lastPathComponent
        let ext = srcURL.pathExtension
        let timeStamp = Int(Date().timeIntervalSince1970)
        let uniqueFileName = "\(originalName)_\(timeStamp).\(ext)"
        
        let destURL = URL(fileURLWithPath: destDirectory).appendingPathComponent(uniqueFileName)
        
        try fileManager.moveItem(at: srcURL, to: destURL)
        
        return destURL
    }

	func documentWasSelected (urls: [URL]) {
		var error: NSError?
        let coordinator = NSFileCoordinator();
        var results: [FileInfo] = [];
        for url in urls {
            coordinator.coordinate(
                readingItemAt: url,
                options: [],
                error: &error
            ) { newURL in
                var finalURL = newURL
                do {
                    finalURL = try self.moveFileToTMP(at: newURL)
                } catch {
                    self.sendError("Failed to move file: \(error.localizedDescription)")
                }
                
                let result = FileInfo(
                    mediaType: self.detectMimeType(finalURL),
                    name: finalURL.lastPathComponent,
                    uri: finalURL.absoluteString
                )

                results.append(result);
                
                newURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let jsonData = try JSONEncoder().encode(results)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            self.send(jsonString)
        }
        catch {
            self.sendError("Serializing result failed.")
        }
        
		if let error = error {
			self.sendError(error.localizedDescription)
		}
    }

	// Function to handle the getFiles command from JavaScript
	@objc(getFiles:)
	func getFiles(command: CDVInvokedUrlCommand) {
		self.commandCallback = command.callbackId

		let accept = command.arguments.first as! String
        let allowMultipleSelection = command.arguments.count > 1 ? command.arguments[1] as! Bool: false
		let mimeTypes = accept.components(separatedBy: ",")

		let utis = mimeTypes.map { (mimeType: String) -> String in
			switch mimeType {
				case "audio/*":
					return kUTTypeAudio as String
				case "font/*":
					return "public.font"
				case "image/*":
					return kUTTypeImage as String
				case "text/*":
					return kUTTypeText as String
				case "video/*":
					return kUTTypeVideo as String
				default:
					break
			}

			if mimeType.range(of: "*") == nil {
				let utiUnmanaged = UTTypeCreatePreferredIdentifierForTag(
					kUTTagClassMIMEType,
					mimeType as CFString,
					nil
				)

				if let uti = (utiUnmanaged?.takeRetainedValue() as? String) {
					if !uti.hasPrefix("dyn.") {
						return uti
					}
				}
			}

			return kUTTypeData as String
		}

        self.callPicker(utis: utis, allowMultipleSelection: allowMultipleSelection)
	}

	func send (_ message: String, _ status: CDVCommandStatus = CDVCommandStatus_OK) {
		if let callbackId = self.commandCallback {
			self.commandCallback = nil

			let pluginResult = CDVPluginResult(
				status: status,
				messageAs: message
			)

			self.commandDelegate!.send(
				pluginResult,
				callbackId: callbackId
			)
		}
	}

	func sendError (_ message: String) {
		self.send(message, CDVCommandStatus_ERROR)
	}
}

extension Chooser : UIDocumentPickerDelegate {
	@available(iOS 11.0, *)
	func documentPicker (
		_ controller: UIDocumentPickerViewController,
		didPickDocumentsAt urls: [URL]
	) {
        self.documentWasSelected(urls: urls)
	}

	func documentPicker (
		_ controller: UIDocumentPickerViewController,
		didPickDocumentAt url: URL
	) {
		self.documentWasSelected(urls: [url])
	}

	func documentPickerWasCancelled (_ controller: UIDocumentPickerViewController) {
		self.sendError("RESULT_CANCELED")
	}
}
