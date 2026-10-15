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
    // whether the interface was in landscape when x/y/width/height were passed in
    var dimensionsAreLandscape: Bool?

    // Helper to get the current interface orientation via connectedScenes (iOS 15+)
    private func getInterfaceOrientation() -> UIInterfaceOrientation {
        return UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.interfaceOrientation ?? .unknown
    }

    @objc func rotated() {
        // the device orientation notification is posted before the interface has been rotated,
        // so the interface orientation is not updated yet at this point
        DispatchQueue.main.async {
            self.layoutPreview()

            if let transitionCoordinator = self.bridge?.viewController?.transitionCoordinator {
                transitionCoordinator.animate(alongsideTransition: nil) { _ in
                    self.layoutPreview()
                }
            }
        }
    }

    /**
     * Applies the stored dimensions and the current interface orientation to the preview and the capture outputs.
     */
    private func layoutPreview() {
        assert(Thread.isMainThread)

        guard let previewView = self.previewView,
              let x = self.x,
              let y = self.y,
              let width = self.width,
              let height = self.height else {
            return
        }

        let adjustedHeight = self.paddingBottom != nil ? height - self.paddingBottom! : height
        var frame = CGRect(x: x, y: y, width: width, height: adjustedHeight)

        // the dimensions were given for the other orientation (and not updated yet), so rotate them
        let isLandscape = getInterfaceOrientation().isLandscape
        if self.rotateWhenOrientationChanged == true, let dimensionsAreLandscape = self.dimensionsAreLandscape, dimensionsAreLandscape != isLandscape {
            frame = CGRect(x: y, y: x, width: adjustedHeight, height: width)
        }

        previewView.frame = frame
        cameraController.updatePreviewLayerFrame(view: previewView)
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
        // all dimensions are in points (which equal css pixels in the webview)
        self.x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!) : 0
        self.y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!) : 0
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
                    return
                } 
                self.cameraController.prepare(cameraPosition: self.cameraPosition, disableAudio: self.disableAudio) {error in
                    if let error = error {
                        print(error)
                        call.reject(error.localizedDescription)
                        return
                    }
                    guard let height = self.height, let width = self.width else {
                        call.reject("Invalid dimensions")
                        return
                    }

                    let adjustedHeight = self.paddingBottom != nil ? height - self.paddingBottom! : height
                    self.dimensionsAreLandscape = self.getInterfaceOrientation().isLandscape
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

                    self.cameraController.setOnFocusSetCallback(callback: self.onFocusSet)

                    call.resolve()
                }
            }
        }
    }

    @objc func flip(_ call: CAPPluginCall) {
        self.cameraController.sessionQueue.async {
            do {
                try self.cameraController.switchCameras()
            } catch {
                call.reject("failed to flip camera")
                return
            }

            DispatchQueue.main.async {
                // the connections of the new input start with the default orientation
                self.cameraController.updateVideoOrientation()
                call.resolve()
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let captureSession = self.cameraController.captureSession, captureSession.isRunning else {
                call.reject("camera already stopped")
                return
            }

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

            // stopRunning is blocking and takes a while, so it must not block the main thread
            self.cameraController.sessionQueue.async {
                captureSession.stopRunning()
                call.resolve()
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

            let quality = call.getInt("quality", 85)
            let compression = CGFloat(quality) / 100.0
            // the longer side of the requested size is used as limit, so the result does not depend on the orientation
            let maxPixelSize = max(call.getInt("width", 0), call.getInt("height", 0))

            self.cameraController.captureImage(maxPixelSize: maxPixelSize > 0 ? maxPixelSize : nil) { [weak self] (image, error) in
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
        // all dimensions are in points (which equal css pixels in the webview)
        let x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!) : 0
        let y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!) : 0
        let width = call.getInt("width") != nil ? CGFloat(call.getInt("width")!) : UIScreen.main.bounds.size.width
        let height = call.getInt("height") != nil ? CGFloat(call.getInt("height")!) : UIScreen.main.bounds.size.height

        // plugin methods are not called on the main thread, but UIKit/CALayer must only be accessed from there
        DispatchQueue.main.async {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.paddingBottom = call.getInt("paddingBottom") != nil ? CGFloat(call.getInt("paddingBottom")!) : 0
            self.dimensionsAreLandscape = self.getInterfaceOrientation().isLandscape

            self.layoutPreview()
            call.resolve()
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
