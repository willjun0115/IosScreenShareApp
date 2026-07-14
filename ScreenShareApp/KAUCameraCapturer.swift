//
//  KAUCameraCapturer.swift
//  ScreenShareApp
//

import AVFoundation
import WebRTC

class KAUCameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private var rtcManager: WebRTCManager?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    func startCapture(rtcManager: WebRTCManager) {
        self.rtcManager = rtcManager
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            for output in self.captureSession.outputs {
                self.captureSession.removeOutput(output)
            }
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let videoInput = try? AVCaptureDeviceInput(device: videoDevice)
            else {
                self.captureSession.commitConfiguration()
                return
            }
            
            if self.captureSession.canAddInput(videoInput) {
                self.captureSession.addInput(videoInput)
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.data.queue"))
            
            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
            }
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
    
    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
        
        rtcManager?.sendPixelBuffer(pixelBuffer, timeStampNs: timeStampNs)
    }
}
