//
//  CameraViewController.swift
//  PhotoSolutionDemo
//
//  Created by MA XINGCHEN on 13/12/18.
//  Copyright © 2018 mark. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController {
    
    var solutionDelegate:PhotoSolutionDelegate?
    var customization: PhotoSolutionCustomization!
    var podBundle: Bundle!
    var inCameraView: Bool!
    var imageEditView: ImageEditView!
    var lastFaceFocusPoint: CGPoint!
    var cameraArea: UIView!
    
    @IBOutlet weak var settingsView: UIView!
    @IBOutlet weak var rotateCameraButton: UIImageView!
    @IBOutlet weak var cancelCameraButton: UIImageView!
    @IBOutlet weak var takePhotoButton: UIImageView!
    @IBOutlet weak var flashLightButton: UIImageView!
    @IBOutlet weak var settingButton: UIImageView!
    
    @IBOutlet weak var redSlider: UISlider!
    @IBOutlet weak var greenSlider: UISlider!
    @IBOutlet weak var blueSlider: UISlider!
    @IBOutlet weak var autoSwitch: UISwitch!
    @IBOutlet weak var durationSlider: UISlider!
    @IBOutlet weak var isoSlider: UISlider!
    
    var captureSession: AVCaptureSession!
    var currentCaptureDevice: AVCaptureDevice!
    var frontCamera: AVCaptureDevice!
    var backCamera: AVCaptureDevice!
    var stillImageOutput: AVCaptureStillImageOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var timer: Timer!
    
    let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override open var shouldAutorotate: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        inCameraView = true
        settingsView.isHidden = true
        setupUI()
        setupSettingsRange()
        setupFrontAndBackCamera()
        setupSessionAndOutput()
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { response in
            if response {
                PHPhotoLibrary.requestAuthorization { status in
                    DispatchQueue.main.async {
                        switch status {
                        case .authorized:
                            self.setupInput(isBackCamera: true)
                            self.setFaceDetection()
                        case .denied, .restricted:
                            self.goToPhotoAccessSetting()
                        case .notDetermined:
                            self.goToPhotoAccessSetting()
                        @unknown default:
                            fatalError()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.goToCameraAccessSetting()
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector:#selector(didChangeOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if previewLayer == nil{
            setupPreviewLayer()
        }
        if (captureSession.isRunning == false) {
            captureSession.startRunning()
        }
        timer = Timer.scheduledTimer(timeInterval: Double(0.7), target: self, selector: #selector(getLatestCameraStatus), userInfo: nil, repeats: true)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if (captureSession.isRunning == true) {
            captureSession.stopRunning()
        }
        timer.invalidate()
    }
    
    private func setFaceDetection(){
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
        }
        metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
    }
    
    @objc private func getLatestCameraStatus(timer: Timer) -> Void{
        if !settingsView.isHidden && autoSwitch.isOn{
            initSlidersValue()
        }
    }
    
    func restoreCurrentCamera(){
        autoSwitch.setOn(true, animated: true)
        isoSlider.isEnabled = false
        durationSlider.isEnabled = false
        redSlider.isEnabled = false
        greenSlider.isEnabled = false
        blueSlider.isEnabled = false
        do{
            try currentCaptureDevice.lockForConfiguration()
            currentCaptureDevice.exposureMode = .continuousAutoExposure
            if currentCaptureDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance){
                currentCaptureDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if currentCaptureDevice.isFocusModeSupported(.continuousAutoFocus){
                currentCaptureDevice.focusMode = .continuousAutoFocus
            }
            currentCaptureDevice.unlockForConfiguration()
            initSlidersValue()
        }catch {
            print("Error in auto exposure")
        }
    }
    
    func initSlidersValue(){
        let currentISO = currentCaptureDevice.iso
        let currentDuration = currentCaptureDevice.exposureDuration.seconds
        let minISO = currentCaptureDevice.activeFormat.minISO
        let maxISO = currentCaptureDevice.activeFormat.maxISO
        isoSlider.value = (currentISO - minISO)/(maxISO - minISO)
        durationSlider.value = Float(currentDuration)
        
        let minWhiteBalanceGain = Float(1.0)
        let maxWhiteBalanceGain = currentCaptureDevice.maxWhiteBalanceGain
        redSlider.value = (currentCaptureDevice.deviceWhiteBalanceGains.redGain - minWhiteBalanceGain)/(maxWhiteBalanceGain - minWhiteBalanceGain)
        greenSlider.value = (currentCaptureDevice.deviceWhiteBalanceGains.greenGain - minWhiteBalanceGain)/(maxWhiteBalanceGain - minWhiteBalanceGain)
        blueSlider.value = (currentCaptureDevice.deviceWhiteBalanceGains.blueGain - minWhiteBalanceGain)/(maxWhiteBalanceGain - minWhiteBalanceGain)
    }
    
    @IBAction func autoSwitch(_ sender: UISwitch) {
        if autoSwitch.isOn{
            restoreCurrentCamera()
        }else{
            isoSlider.isEnabled = true
            durationSlider.isEnabled = true
            redSlider.isEnabled = true
            greenSlider.isEnabled = true
            blueSlider.isEnabled = true
        }
    }
    
    func setupSettingsRange(){
        isoSlider.minimumValue = 0.01
        isoSlider.maximumValue = 0.99
        durationSlider.minimumValue = 0.0001
        durationSlider.maximumValue = 0.1999
    }
    
    func customExposure(){
        do{
            try currentCaptureDevice.lockForConfiguration()
            let minISO = currentCaptureDevice.activeFormat.minISO
            let maxISO = currentCaptureDevice.activeFormat.maxISO
            let clampedISO = isoSlider.value * (maxISO - minISO) + minISO
            let sTime = CMTime(seconds: Double(durationSlider.value), preferredTimescale: 1000000)
            currentCaptureDevice.setExposureModeCustom(duration: sTime, iso: clampedISO, completionHandler: { (time) -> Void in
                //Todo
            })
            currentCaptureDevice.unlockForConfiguration()
        }catch {
            print("Error in customExposure")
        }
    }
    
    func customWhiteBalance(){
        do{
            try currentCaptureDevice.lockForConfiguration()
            let minWhiteBalanceGain = Float(1.0)
            let maxWhiteBalanceGain = currentCaptureDevice.maxWhiteBalanceGain
            let redValue = redSlider.value * (maxWhiteBalanceGain - minWhiteBalanceGain) + minWhiteBalanceGain
            let greenValue = greenSlider.value * (maxWhiteBalanceGain - minWhiteBalanceGain) + minWhiteBalanceGain
            let blueValue = blueSlider.value * (maxWhiteBalanceGain - minWhiteBalanceGain) + minWhiteBalanceGain
            let whiteBalanceGains = AVCaptureDevice.WhiteBalanceGains(redGain: redValue, greenGain: greenValue, blueGain: blueValue)
            currentCaptureDevice.setWhiteBalanceModeLocked(with: whiteBalanceGains) { (CMTime) in
                //Todo
            }
            currentCaptureDevice.unlockForConfiguration()
        }catch {
            print("Error in whiteBalance")
        }
    }
    
    @IBAction func durationSlide(_ sender: UISlider) {
        customExposure()
    }
    
    @IBAction func ISOSlide(_ sender: UISlider) {
        customExposure()
    }
    
    @IBAction func redSlide(_ sender: UISlider) {
        customWhiteBalance()
    }
    
    @IBAction func greenSlide(_ sender: UISlider) {
        customWhiteBalance()
    }
    
    @IBAction func blueSlide(_ sender: UISlider) {
        customWhiteBalance()
    }
    
    
    func setupFrontAndBackCamera(){
        if let devices = AVCaptureDevice.devices(for: AVMediaType.video) as [AVCaptureDevice]? {
            for device in devices {
                if(device.position == AVCaptureDevice.Position.back) {
                    backCamera = device
                }else if(device.position == AVCaptureDevice.Position.front){
                    frontCamera = device
                }
            }
            currentCaptureDevice = backCamera
        }
    }
    
    func setupSessionAndOutput(){
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        stillImageOutput = AVCaptureStillImageOutput()
        //stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        if captureSession.canAddOutput(stillImageOutput) {
            captureSession.addOutput(stillImageOutput)
        }else{
            //Todo
        }
        if let connection = self.stillImageOutput.connection(with: AVMediaType.video) {
            if (self.currentCaptureDevice?.activeFormat.isVideoStabilizationModeSupported(.auto))! {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
    }
    
    func setupInput(isBackCamera: Bool){
        if(previewLayer != nil){
            let animation: CATransition = CATransition()
            animation.duration = 0.5
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.type = CATransitionType(rawValue: "oglFlip")
            if(isBackCamera){
                animation.subtype = CATransitionSubtype.fromLeft
            }else{
                animation.subtype = CATransitionSubtype.fromRight
            }
            previewLayer.add(animation, forKey: nil)
        }
        do {
            self.captureSession.beginConfiguration()
            if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    captureSession.removeInput(input)
                }
            }
            if(isBackCamera){
                currentCaptureDevice = backCamera
            }else{
                currentCaptureDevice = frontCamera
            }
            try self.captureSession.addInput(AVCaptureDeviceInput(device: self.currentCaptureDevice))
            self.captureSession.commitConfiguration()
            DispatchQueue.main.async{
                if self.currentCaptureDevice.isFlashModeSupported(.auto){
                    self.flashLightButton.isHidden = false
                    self.setupFlashMode(isOn: false)
                }else{
                    self.flashLightButton.isHidden = true
                }
                self.restoreCurrentCamera()
            }
        } catch {
            print("Error")
        }
    }
    
    func setupUI(){
        rotateCameraButton.image = UIImage(named: "switchIcon", in: self.podBundle, compatibleWith: nil)
        takePhotoButton.image = UIImage(named: "cameraIcon", in: self.podBundle, compatibleWith: nil)
        cancelCameraButton.image = UIImage(named: "cancelIcon", in: self.podBundle, compatibleWith: nil)
        flashLightButton.image = UIImage(named: "flashOff", in: self.podBundle, compatibleWith: nil)
        settingButton.image = UIImage(named: "settingsToOpen", in: self.podBundle, compatibleWith: nil)
        settingButton.isHidden = true
        
        settingsView.layer.masksToBounds = true
        settingsView.layer.cornerRadius = 15
        settingsView.layer.borderWidth = 2
        settingsView.layer.borderColor = UIColor.white.cgColor
        
        let tapRotateCameraButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(rotateCameraButtonTapped(tapGestureRecognizer:)))
        rotateCameraButton.isUserInteractionEnabled = true
        rotateCameraButton.addGestureRecognizer(tapRotateCameraButtonRecognizer)
        
        let tapCancelCameraButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(cancelCameraButtonTapped(tapGestureRecognizer:)))
        cancelCameraButton.isUserInteractionEnabled = true
        cancelCameraButton.addGestureRecognizer(tapCancelCameraButtonRecognizer)
        
        let tapTakePhotoButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapTakePhotoButtonTapped(tapGestureRecognizer:)))
        takePhotoButton.isUserInteractionEnabled = true
        takePhotoButton.addGestureRecognizer(tapTakePhotoButtonRecognizer)
        
        let tapFlashLightButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapFlashLightButtonTapped(tapGestureRecognizer:)))
        flashLightButton.isUserInteractionEnabled = true
        flashLightButton.addGestureRecognizer(tapFlashLightButtonRecognizer)
        
        let tapSettingButtonRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapSettingButtonTapped(tapGestureRecognizer:)))
        settingButton.isUserInteractionEnabled = true
        settingButton.addGestureRecognizer(tapSettingButtonRecognizer)
        
        let tapSettingsViewRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapSettingsViewTapped(tapGestureRecognizer:)))
        settingsView.isUserInteractionEnabled = true
        settingsView.addGestureRecognizer(tapSettingsViewRecognizer)
        
        imageEditView = UINib(nibName: "ImageEditView", bundle: self.podBundle).instantiate(withOwner: nil, options: nil)[0] as? ImageEditView
    }
    
    @objc func tapSettingButtonTapped(tapGestureRecognizer: UITapGestureRecognizer){
        if !settingsView.isHidden{
            settingsView.isHidden = true
            settingButton.image = UIImage(named: "settingsToOpen", in: self.podBundle, compatibleWith: nil)
        }else{
            settingsView.isHidden = false
            settingButton.image = UIImage(named: "settingsToClose", in: self.podBundle, compatibleWith: nil)
            initSlidersValue()
        }
    }
    
    @objc func rotateCameraButtonTapped(tapGestureRecognizer: UITapGestureRecognizer){
        if(currentCaptureDevice == frontCamera){
            setupInput(isBackCamera: true)
        }else{
            setupInput(isBackCamera: false)
        }
    }
    
    @objc func cancelCameraButtonTapped(tapGestureRecognizer: UITapGestureRecognizer){
        self.solutionDelegate?.pickerCancel()
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func tapSettingsViewTapped(tapGestureRecognizer: UITapGestureRecognizer){
        let point: CGPoint = tapGestureRecognizer.location(in: cameraArea)
        focus(at: point)
    }
    
    func imageRotatedByDegrees(oldImage: UIImage, deg degrees: CGFloat) -> UIImage {
        //Calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox: UIView = UIView(frame: CGRect(x: 0, y: 0, width: oldImage.size.width, height: oldImage.size.height))
        let t: CGAffineTransform = CGAffineTransform(rotationAngle: degrees * CGFloat.pi / 180)
        rotatedViewBox.transform = t
        let rotatedSize: CGSize = rotatedViewBox.frame.size
        //Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap: CGContext = UIGraphicsGetCurrentContext()!
        //Move the origin to the middle of the image so we will rotate and scale around the center.
        bitmap.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        //Rotate the image context
        bitmap.rotate(by: (degrees * CGFloat.pi / 180))
        //Now, draw the rotated/scaled image into the context
        bitmap.scaleBy(x: 1.0, y: -1.0)
        bitmap.draw(oldImage.cgImage!, in: CGRect(x: -oldImage.size.width / 2, y: -oldImage.size.height / 2, width: oldImage.size.width, height: oldImage.size.height))
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }
    
    @objc func tapTakePhotoButtonTapped(tapGestureRecognizer: UITapGestureRecognizer){
        self.stillImageOutput.captureStillImageAsynchronously(from: self.stillImageOutput.connection(with: AVMediaType.video)!) { (buffer, error) in
            if buffer == nil {
                return
            }else{
                let originalImageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer!)
                let originalImage = UIImage(data: originalImageData!)
                
                //compress or not
                var image = originalImage?.rescaleImage(toPX: 1500)
                
                if UIDevice.current.orientation == .landscapeLeft{
                    image = image!.rotate(radians: -.pi/2)
                }else if UIDevice.current.orientation == .landscapeRight{
                    image = image!.rotate(radians: .pi/2)
                }
                
                self.imageEditView.frame = self.cameraArea.frame
                self.imageEditView.setupImage(edittingImage: image!, fromCamera: true)
                self.imageEditView.delegate = self
                self.view.addSubview(self.imageEditView)
                self.inCameraView = false
            }
        }
    }
    
    @objc func tapFlashLightButtonTapped(tapGestureRecognizer: UITapGestureRecognizer){
        setupFlashMode(isOn: currentCaptureDevice.flashMode != .on)
    }
    
    func setupFlashMode(isOn: Bool){
        do {
            try currentCaptureDevice.lockForConfiguration()
            if isOn{
                currentCaptureDevice.flashMode = .auto
            }else{
                currentCaptureDevice.flashMode = .off
            }
            currentCaptureDevice.unlockForConfiguration()
            DispatchQueue.main.async{
                if isOn{
                    self.flashLightButton.image = UIImage(named: "flashOn", in: self.podBundle, compatibleWith: nil)
                }else{
                    self.flashLightButton.image = UIImage(named: "flashOff", in: self.podBundle, compatibleWith: nil)
                    
                }
            }
        } catch {
            print("Error in FlashLight")
        }
    }
    
    func setupPreviewLayer() {
        var topSafeAreaPadding: CGFloat = 0
        var bottomSafeAreaPadding: CGFloat = 0
        if #available(iOS 11.0, *) {
            topSafeAreaPadding = UIApplication.shared.keyWindow!.safeAreaInsets.top
            bottomSafeAreaPadding = UIApplication.shared.keyWindow!.safeAreaInsets.bottom
        }
        cameraArea = UIView.init(frame:CGRect.init(x: 0, y: topSafeAreaPadding, width: self.view.frame.width, height: self.view.frame.height-topSafeAreaPadding-bottomSafeAreaPadding))
        self.view.addSubview(cameraArea)
        self.view.sendSubviewToBack(cameraArea)
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer?.bounds = self.cameraArea.bounds
        self.previewLayer?.position = CGPoint(x: self.cameraArea.bounds.midX, y: self.cameraArea.bounds.midY)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
        self.cameraArea.layer.addSublayer(self.previewLayer!)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.focusGesture(_:)))
        self.cameraArea.addGestureRecognizer(tapGesture)
        focus(at: CGPoint(x: self.cameraArea.bounds.midX, y: self.cameraArea.bounds.midY))
        
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(self.pinchView(_:)))
        self.cameraArea.addGestureRecognizer(pinchGestureRecognizer)
        self.cameraArea.isUserInteractionEnabled = true
        self.cameraArea.isMultipleTouchEnabled = true
        
        focusView.layer.borderWidth = 1.0
        focusView.layer.borderColor = UIColor.yellow.cgColor
        focusView.backgroundColor = UIColor.clear
        self.cameraArea.addSubview(focusView)
        focusView.isHidden = true
    }
    
    @objc func pinchView(_ pinchGestureRecognizer: UIPinchGestureRecognizer) {
        let pinchVelocityDividerFactor: CGFloat = 20
        if pinchGestureRecognizer.state == .changed {
            do{
                try currentCaptureDevice.lockForConfiguration()
                let desiredZoomFactor: CGFloat = currentCaptureDevice.videoZoomFactor + CGFloat(atan2f(Float(pinchGestureRecognizer.velocity), Float(pinchVelocityDividerFactor)))
                currentCaptureDevice.videoZoomFactor = max(1.0, min(desiredZoomFactor, currentCaptureDevice.activeFormat.videoMaxZoomFactor))
                currentCaptureDevice.unlockForConfiguration()
            }catch {
                print("Error in Focus")
            }
        }
    }
    
    @objc func focusGesture(_ gesture: UITapGestureRecognizer) {
        let point: CGPoint = gesture.location(in: cameraArea)
        focus(at: point)
    }
    
    func focus(at point: CGPoint) {
        let size: CGSize = cameraArea.bounds.size
        let focusPoint = CGPoint(x: point.y / size.height, y: 1 - point.x / size.width)
        do {
            try currentCaptureDevice.lockForConfiguration()
            if currentCaptureDevice.isFocusModeSupported(.autoFocus) {
                currentCaptureDevice.focusPointOfInterest = focusPoint
                currentCaptureDevice.focusMode = .continuousAutoFocus
            }
            if currentCaptureDevice.isExposureModeSupported(.autoExpose) {
                currentCaptureDevice.exposurePointOfInterest = focusPoint
                currentCaptureDevice.exposureMode = .continuousAutoExposure
            }
            currentCaptureDevice.unlockForConfiguration()
            DispatchQueue.main.async{
                self.focusView.center = point
                self.focusView.isHidden = false
                UIView.animate(withDuration: 0.3, animations: {
                    self.focusView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                }) { finished in
                    UIView.animate(withDuration: 0.3, animations: {
                        self.focusView.transform = CGAffineTransform.identity
                    }) { finished in
                        self.focusView.isHidden = true
                    }
                }
            }
        } catch {
            print("Error in Focus")
        }
    }
    
    func goToPhotoAccessSetting(){
        let alert = UIAlertController(title: nil, message: customization.alertTextForPhotoAccess, preferredStyle: .alert)
        alert.addAction( UIAlertAction(title: customization.settingButtonTextForPhotoAccess, style: .cancel, handler: { action in
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(NSURL(string:UIApplication.openSettingsURLString)! as URL, options: [:]) { (_) in
                    self.dismiss(animated: false, completion: nil)
                }
            } else {
                UIApplication.shared.openURL(NSURL(string:UIApplication.openSettingsURLString)! as URL)
                self.dismiss(animated: false, completion: nil)
            }
        }))
        alert.addAction( UIAlertAction(title: customization.cancelButtonTextForPhotoAccess, style: .default, handler: { action in
            self.solutionDelegate?.pickerCancel()
            self.dismiss(animated: true, completion: nil)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func goToCameraAccessSetting(){
        let alert = UIAlertController(title: nil, message: self.customization.alertTextForCameraAccess, preferredStyle: .alert)
        alert.addAction( UIAlertAction(title: self.customization.settingButtonTextForCameraAccess, style: .cancel, handler: { action in
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(NSURL(string:UIApplication.openSettingsURLString)! as URL, options: [:]) { (_) in
                    self.dismiss(animated: false, completion: nil)
                }
            } else {
                UIApplication.shared.openURL(NSURL(string:UIApplication.openSettingsURLString)! as URL)
                self.dismiss(animated: false, completion: nil)
            }
        }))
        alert.addAction( UIAlertAction(title: self.customization.cancelButtonTextForCameraAccess, style: .default, handler: { action in
            self.solutionDelegate?.pickerCancel()
            self.dismiss(animated: true, completion: nil)
        }))
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func didChangeOrientation() {
        UIView.animate(withDuration: 0.3, animations: {
            if UIDevice.current.orientation == .landscapeLeft{
                self.rotateCameraButton.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
                self.flashLightButton.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
            }else if UIDevice.current.orientation == .landscapeRight{
                self.rotateCameraButton.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi / 2))
                self.flashLightButton.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi / 2))
            }else{
                self.rotateCameraButton.transform = CGAffineTransform.identity
                self.flashLightButton.transform = CGAffineTransform.identity
            }
        })
    }
    
    func distanceBetween(_ p1: CGPoint, and p2: CGPoint) -> CGFloat {
        return sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
    }

}

extension CameraViewController: ImageEditViewDelegate{
    
    func imageCompleted(_ editedImage: UIImage) {
        self.dismiss(animated: false) {
            self.solutionDelegate?.returnImages([editedImage])
        }
    }
    
}

extension CameraViewController: AVCaptureMetadataOutputObjectsDelegate{
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection){
        for metadataObject in metadataObjects {
            if metadataObject.type == AVMetadataObject.ObjectType.face {
                let transformedMetadataObject = previewLayer.transformedMetadataObject(for: metadataObject)
                let currentFacePoint = CGPoint(x: (transformedMetadataObject?.bounds.midX)!, y: (transformedMetadataObject?.bounds.midY)!)
                if lastFaceFocusPoint == nil || distanceBetween(currentFacePoint,and: lastFaceFocusPoint) > 100{
                    focus(at: currentFacePoint)
                    lastFaceFocusPoint = currentFacePoint
                }
            }
        }
    }
    
}
