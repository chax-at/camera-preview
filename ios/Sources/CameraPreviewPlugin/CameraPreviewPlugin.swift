import Foundation
import Capacitor
import AVFoundation
import UIKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CameraPreview)
public class CameraPreview: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "CameraPreviewPlugin"
    public let jsName = "CameraPreview"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "capture", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "captureSample", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "flip", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSupportedFlashModes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFlashMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startRecordVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopRecordVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isCameraStarted", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSupportedPictureSizes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getFlashMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setPreviewDimensions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "subscribeToFocusSet", returnType: CAPPluginReturnCallback)
    ]

    var previewView: UIView!
    var cameraPosition = String()
    let cameraController = CameraController()
    // swiftlint:disable identifier_name
    var x: CGFloat?
    var y: CGFloat?
    // swiftlint:enable identifier_name
    var width: CGFloat?
    var height: CGFloat?
    var paddingBottom: CGFloat?
    var rotateWhenOrientationChanged: Bool?
    var toBack: Bool?
    var storeToFile: Bool?
    var enableZoom: Bool?
    var highResolutionOutput: Bool = false
    var disableAudio: Bool = false
    var onFocusSetCallbackId: String? = nil

    // Helper to get the current interface orientation via connectedScenes (iOS 15+)
    private func getInterfaceOrientation() -> UIInterfaceOrientation {
        return UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.interfaceOrientation ?? .unknown
    }

    @objc func rotated() {
        guard let previewView = self.previewView,
              let x = self.x,
              let y = self.y,
              let width = self.width,
              let height = self.height else {
            return
        }

        let adjustedHeight = self.paddingBottom != nil ? height - self.paddingBottom! : height
        let orientation = getInterfaceOrientation()

        if orientation.isLandscape {
            previewView.frame = CGRect(x: y, y: x, width: max(adjustedHeight, width), height: min(adjustedHeight, width))
            self.cameraController.previewLayer?.frame = previewView.frame
        }

        if orientation.isPortrait {
            previewView.frame = CGRect(x: x, y: y, width: min(adjustedHeight, width), height: max(adjustedHeight, width))
            self.cameraController.previewLayer?.frame = previewView.frame
        }

        cameraController.updateVideoOrientation()
    }
    
    @objc func onFocusSet(screenPosition: CGPoint) {
        if self.onFocusSetCallbackId != nil {
            let call = self.bridge?.savedCall(withID: self.onFocusSetCallbackId!)
            if call != nil {
                call!.resolve(["x": screenPosition.x, "y": screenPosition.y])
            }
        }
    }

    @objc func start(_ call: CAPPluginCall) {
        self.cameraPosition = call.getString("position") ?? "rear"
        self.highResolutionOutput = call.getBool("enableHighResolution") ?? false
        self.cameraController.highResolutionOutput = self.highResolutionOutput

        if call.getInt("width") != nil {
            self.width = CGFloat(call.getInt("width")!)
        } else {
            self.width = UIScreen.main.bounds.size.width
        }
        if call.getInt("height") != nil {
            self.height = CGFloat(call.getInt("height")!)
        } else {
            self.height = UIScreen.main.bounds.size.height
        }
        self.x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!)/UIScreen.main.scale: 0
        self.y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!)/UIScreen.main.scale: 0
        if call.getInt("paddingBottom") != nil {
            self.paddingBottom = CGFloat(call.getInt("paddingBottom")!)
        }

        self.rotateWhenOrientationChanged = call.getBool("rotateWhenOrientationChanged") ?? true
        self.toBack = call.getBool("toBack") ?? false
        self.storeToFile = call.getBool("storeToFile") ?? false
        self.enableZoom = call.getBool("enableZoom") ?? false
        self.disableAudio = call.getBool("disableAudio") ?? false

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                call.reject("Camera permission denied")
                return
            }

            DispatchQueue.main.async {
                if self.cameraController.captureSession?.isRunning ?? false {
                    call.reject("camera already started")
                } else {
                    self.cameraController.prepare(cameraPosition: self.cameraPosition, disableAudio: self.disableAudio) {error in
                        if let error = error {
                            print(error)
                            call.reject(error.localizedDescription)
                            return
                        }
                        let height = self.paddingBottom != nil ? self.height! - self.paddingBottom!: self.height!
                        self.previewView = UIView(frame: CGRect(x: self.x ?? 0, y: self.y ?? 0, width: self.width!, height: height))
                        self.webView?.isOpaque = false
                        self.webView?.backgroundColor = UIColor.clear
                        self.webView?.scrollView.backgroundColor = UIColor.clear
                        self.webView?.superview?.addSubview(self.previewView)
                        if self.toBack! {
                            self.webView?.superview?.bringSubviewToFront(self.webView!)
                        }
                        try? self.cameraController.displayPreview(on: self.previewView)

                        let frontView = self.toBack! ? self.webView : self.previewView
                        self.cameraController.setupGestures(target: frontView ?? self.previewView, enableZoom: self.enableZoom!)

                        if self.rotateWhenOrientationChanged == true {
                            NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
                        }

                        self.cameraController.setOnFocusSetCallback(callback: self.onFocusSet)

                        call.resolve()

                    }
                    guard let height = self.height, let width = self.width else {
                        call.reject("Invalid dimensions")
                        return
                    }

                    let adjustedHeight = self.paddingBottom != nil ? height - self.paddingBottom! : height
                    self.previewView = UIView(frame: CGRect(x: self.x ?? 0, y: self.y ?? 0, width: width, height: adjustedHeight))
                    self.webView?.isOpaque = false
                    self.webView?.backgroundColor = UIColor.clear
                    self.webView?.scrollView.backgroundColor = UIColor.clear
                    self.webView?.superview?.addSubview(self.previewView)
                    if let toBack = self.toBack, toBack {
                        self.webView?.superview?.bringSubviewToFront(self.webView!)
                    }
                    try? self.cameraController.displayPreview(on: self.previewView)

                    let frontView = (self.toBack ?? false) ? self.webView : self.previewView
                    self.cameraController.setupGestures(target: frontView ?? self.previewView, enableZoom: self.enableZoom ?? false)

                    if self.rotateWhenOrientationChanged == true {
                        NotificationCenter.default.addObserver(self, selector: #selector(CameraPreview.rotated), name: UIDevice.orientationDidChangeNotification, object: nil)
                    }

                    call.resolve()
                }
            }
        }
    }

    @objc func flip(_ call: CAPPluginCall) {
        do {
            try self.cameraController.switchCameras()
            call.resolve()
        } catch {
            call.reject("failed to flip camera")
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.cameraController.captureSession?.isRunning ?? false {
                self.cameraController.captureSession?.stopRunning()

                // Remove the orientation observer to prevent crashes
                if self.rotateWhenOrientationChanged == true {
                    NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
                }

                if let previewView = self.previewView {
                    previewView.removeFromSuperview()
                    self.previewView = nil
                }
                self.webView?.isOpaque = true
                if self.onFocusSetCallbackId != nil {
                    self.bridge?.releaseCall(withID: self.onFocusSetCallbackId!)
                    self.onFocusSetCallbackId = nil
                }
                call.resolve()
            } else {
                call.reject("camera already stopped")
            }
        }
    }
    
    // Get user's cache directory path
    @objc func getTempFilePath() -> URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName = "cpcp_capture_" + finalIdentifier + ".jpg"

        return path.appendingPathComponent(fileName)
    }

    @objc func capture(_ call: CAPPluginCall) {
        DispatchQueue.main.async {

            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureImage { [weak self] (image, error) in
                guard let self = self else { return }
                
                if let error = error {
                    call.reject(error.localizedDescription)
                    return
                }

                guard let image = image else {
                    call.reject("Image capture failed: no data received")
                    return
                }
                let imageData: Data?
                if self.cameraController.currentCameraPosition == .front {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }

                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve(["value": fileUrl.absoluteString])
                    } catch {
                        call.reject("error writing image to file")
                    }
                }
            }
        }
    }

    @objc func captureSample(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let quality = call.getInt("quality", 85)

            self.cameraController.captureSample { image, error in
                guard let image = image else {
                    print("Image capture error: \(String(describing: error))")
                    call.reject("Image capture error: \(String(describing: error))")
                    return
                }

                let imageData: Data?
                let compression = CGFloat(quality) / 100.0

                if self.cameraPosition == "front" {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: compression)
                } else {
                    imageData = image.jpegData(compressionQuality: compression)
                }

                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve(["value": fileUrl.absoluteString])
                    } catch {
                        call.reject("Error writing image to file")
                    }
                }
            }
        }
    }

    @objc func getSupportedFlashModes(_ call: CAPPluginCall) {
        do {
            let supportedFlashModes = try self.cameraController.getSupportedFlashModes()
            call.resolve(["flashModes": supportedFlashModes])
        } catch {
            call.reject("failed to get supported flash modes")
        }
    }
    
    @objc func getFlashMode(_ call: CAPPluginCall) {
        var flashModeValue: String = ""
        do {
            if(try self.cameraController.isTorchSupported()) {
                let torchMode = try self.cameraController.getTorchMode()
                if torchMode == AVCaptureDevice.TorchMode.on || torchMode == AVCaptureDevice.TorchMode.auto {
                    flashModeValue = "torch"
                    call.resolve(["flashMode": flashModeValue]);
                }
            }
        } catch {
            call.reject("failed to get torch mode")
        }
        
        let flashMode = self.cameraController.getFlashMode();
        
        switch flashMode {
        case AVCaptureDevice.FlashMode.off:
            flashModeValue = "off"
        case AVCaptureDevice.FlashMode.on:
            flashModeValue = "on"
        case AVCaptureDevice.FlashMode.auto:
            flashModeValue = "auto"
        default: break
        }
        
        guard !flashModeValue.isEmpty else {
            call.reject("failed to get flash mode.")
            return
        }
        
        call.resolve(["flashMode": flashModeValue]);
    }

    @objc func setFlashMode(_ call: CAPPluginCall) {
        guard let flashMode = call.getString("flashMode") else {
            call.reject("flashMode parameter is required")
            return
        }
        
        do {
            var flashModeAsEnum: AVCaptureDevice.FlashMode?
            switch flashMode {
            case "off":
                flashModeAsEnum = .off
            case "on":
                flashModeAsEnum = .on
            case "auto":
                flashModeAsEnum = .auto
            default: break
            }
            
            if flashModeAsEnum != nil {
                try self.cameraController.setFlashMode(flashMode: flashModeAsEnum!)
            } else if flashMode == "torch" {
                try self.cameraController.setTorchMode()
            } else {
                call.reject("Flash Mode not supported")
                return
            }
            call.resolve()
        } catch {
            call.reject("failed to set flash mode")
        }
    }
    
    @objc func getSupportedPictureSizes(_ call: CAPPluginCall) {
        do {
            let supportedPictureSizes = try self.cameraController.getSupportedPictureSizes()
            if supportedPictureSizes == nil {
                call.reject("failed to get supportet picture sizes")
            }
            call.resolve(["result": supportedPictureSizes])
        } catch {
            call.reject("failed to get supportet picture sizes")
        }
    }

    @objc func setPreviewDimensions(_ call: CAPPluginCall) {
        let x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!)/UIScreen.main.scale : 0
        let y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!)/UIScreen.main.scale : 0
        let width = call.getInt("width") != nil ? CGFloat(call.getInt("width")!) : UIScreen.main.bounds.size.width
        let height = call.getInt("height") != nil ? CGFloat(call.getInt("height")!) : UIScreen.main.bounds.size.height
        do {
            try self.cameraController.setPreviewDimensions(x: x, y: y, width: width, height: height)
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.paddingBottom = call.getInt("paddingBottom") != nil ? CGFloat(call.getInt("paddingBottom")!) : 0
            call.resolve()
        } catch {
            call.reject("failed to set preview dimensions")
        }
    }

    @objc func startRecordVideo(_ call: CAPPluginCall) {
        DispatchQueue.main.async {

            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureVideo { (image, error) in

                guard let image = image else {
                    print(error ?? "Image capture error")
                    guard let error = error else {
                        call.reject("Image capture error")
                        return
                    }
                    call.reject(error.localizedDescription)
                    return
                }

                // self.videoUrl = image

                call.resolve(["value": image.absoluteString])
            }
        }
    }

    @objc func stopRecordVideo(_ call: CAPPluginCall) {

        self.cameraController.stopRecording { (_) in

        }
    }

    @objc func subscribeToFocusSet(_ call: CAPPluginCall) {
        if self.onFocusSetCallbackId != nil {
            self.bridge?.releaseCall(withID: self.onFocusSetCallbackId!)
            self.onFocusSetCallbackId = nil
        }

        self.onFocusSetCallbackId = call.callbackId
        call.keepAlive = true
    }

    @objc func isCameraStarted(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.cameraController.captureSession?.isRunning ?? false {
                call.resolve(["value": true])
            } else {
                call.resolve(["value": false])
            }
        }
    }
}
