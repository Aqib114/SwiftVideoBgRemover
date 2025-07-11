//
//  ViewModel.swift
//  VideoBgRemover
//
//  Created by Mapple.pk on 10/07/2025.
//

import Foundation
import UIKit
import Vision
import AVFoundation
import Photos
import CoreImage.CIFilterBuiltins

final class VideoProcessingViewModel {
    let context = CIContext()
    let request = VNGenerateForegroundInstanceMaskRequest()
    
    init() {
        print("ViewModel init called")
    }
    
    deinit {
        print("ViewModel deinit called")
    }
}

// MARK: - Frame Extraction
extension VideoProcessingViewModel {
    func extractFrames(
        from url: URL,
        frameRate: Int = 1,
        completion: @escaping (Result<[UIImage], Error>) -> Void
    ) {
        guard frameRate > 0 else {
            completion(.failure(FrameExtractionError.invalidFrameRate))
            return
        }

        let asset = AVAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
            guard let self = self else { return }
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            guard status == .loaded else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? FrameExtractionError.assetLoadingFailed))
                }
                return
            }
            
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration > 0 else {
                DispatchQueue.main.async {
                    completion(.failure(FrameExtractionError.invalidDuration))
                }
                return
            }
            
            let batchSize = self.adaptiveBatchSize(for: asset, frameRate: frameRate)
            let frameTimes = self.generateFrameTimes(for: duration, frameRate: frameRate)
            
            guard !frameTimes.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(FrameExtractionError.noFramesGenerated))
                }
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {[weak self] in
                guard let self = self else {return}
                self.extractBatches(from: asset, times: frameTimes, batchSize: batchSize) { result in
                    DispatchQueue.main.async {
                        completion(result)
                    }
                }
            }
        }
    }
        func getVideoFrameRate(from url: URL) async -> Double? {
            let asset = AVAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            if let frameRate = try? await track.load(.nominalFrameRate) {
                return Double(frameRate)
            }
            return nil
        }
    
    private func adaptiveBatchSize(for asset: AVAsset, frameRate: Int) -> Int {
        guard let track = asset.tracks(withMediaType: .video).first else { return 10 }
        let resolution = track.naturalSize.width * track.naturalSize.height
        if resolution > 1920 * 1080 {
            return max(5, frameRate / 2)
        } else if resolution > 1280 * 720 {
            return max(10, frameRate)
        } else {
            return max(15, frameRate * 2)
        }
    }

    private func generateFrameTimes(for duration: Double, frameRate: Int) -> [NSValue] {
        stride(from: 0.0, to: duration, by: 1.0 / Double(frameRate))
            .map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
    }

    private func extractBatches(
        from asset: AVAsset,
        times: [NSValue],
        batchSize: Int,
        completion: @escaping (Result<[UIImage], Error>) -> Void
    ) {
        var allFrames: [UIImage] = []
        var allErrors: [Error] = []
        
        let totalBatches = Int(ceil(Double(times.count) / Double(batchSize)))

        for batchIndex in 0..<totalBatches {
            let start = batchIndex * batchSize
            let end = min(start + batchSize, times.count)
            let batch = Array(times[start..<end])

            let group = DispatchGroup()
            group.enter()
            generateFrames(from: asset, at: batch) { result in
                switch result {
                case .success(let frames):
                    allFrames.append(contentsOf: frames)
                case .failure(let error):
                    allErrors.append(error)
                }
                group.leave()
            }
            group.wait()
        }

        if !allErrors.isEmpty && allFrames.isEmpty {
            completion(.failure(FrameExtractionError.frameExtractionFailed(allErrors)))
        } else {
            completion(.success(allFrames))
        }
    }

    private func generateFrames(
        from asset: AVAsset,
        at times: [NSValue],
        completion: @escaping (Result<[UIImage], Error>) -> Void
    ) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var images: [UIImage] = []
        var errors: [Error] = []
        let group = DispatchGroup()

        for time in times {
            group.enter()
            generator.generateCGImagesAsynchronously(forTimes: [time]) { _, cgImage, _, result, error in
                defer { group.leave() }
                switch result {
                case .succeeded where cgImage != nil:
                    images.append(UIImage(cgImage: cgImage!))
                case .failed where error != nil:
                    errors.append(error!)
                default:
                    break
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if !errors.isEmpty && images.isEmpty {
                completion(.failure(FrameExtractionError.frameExtractionFailed(errors)))
            } else {
                completion(.success(images))
            }
        }
    }
    
    enum FrameExtractionError: Error, LocalizedError {
        case invalidFrameRate
        case assetLoadingFailed
        case invalidDuration
        case noFramesGenerated
        case frameExtractionFailed([Error])
        
        var errorDescription: String? {
            switch self {
            case .invalidFrameRate: return "Frame rate must be greater than 0."
            case .assetLoadingFailed: return "Could not load video asset."
            case .invalidDuration: return "Invalid video duration."
            case .noFramesGenerated: return "No frames were generated."
            case .frameExtractionFailed(let errors):
                return "Frame extraction failed: \(errors.map { $0.localizedDescription }.joined(separator: ", "))"
            }
        }
    }
}

// MARK: - Background Removal
extension VideoProcessingViewModel {
    func removeBackgrounds(from frames: [UIImage], completion: @escaping (Result<[UIImage], Error>) -> Void) {
        var output: [UIImage] = []
        let queue = DispatchQueue(label: "backgroundRemovalQueue")
        queue.async { [weak self] in
            guard let self = self else { return }
            for frame in frames {
                autoreleasepool {
                    guard let ciImage = CIImage(image: frame) else { return }
                    let mask = self.createMask(for: ciImage)
                    let result = self.applyMask(mask ?? ciImage, to: ciImage)
                    output.append(result)
                }
            }
            DispatchQueue.main.async {
                completion(.success(output))
            }
        }
    }
    
    private func createMask(for image: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image)
        try? handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        return try? CIImage(cvPixelBuffer: observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler))
    }

    private func applyMask(_ mask: CIImage, to image: CIImage) -> UIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        let output = filter.outputImage!
        return render(ciImage: output)
    }

    private func render(ciImage: CIImage) -> UIImage {
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Video Export
extension VideoProcessingViewModel {
    func createVideo(from frames: [UIImage], progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !frames.isEmpty else {
            completion(.failure(NSError(domain: "No frames", code: -1)))
            return
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let size = frames[0].size
        let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer?.add(input)
        writer?.startWriting()
        writer?.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 30)
        var currentTime = CMTime.zero
        let queue = DispatchQueue(label: "videoWritingQueue")

        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let _ = self else { return }
            for (i, frame) in frames.enumerated() {
                autoreleasepool {
                    guard let buffer = frame.toPixelBuffer(size: size) else { return }
                    while !input.isReadyForMoreMediaData { usleep(10_000) }
                     adaptor.append(buffer, withPresentationTime: currentTime)
                    currentTime = CMTimeAdd(currentTime, frameDuration)
                    DispatchQueue.main.async { progress(Double(i + 1) / Double(frames.count)) }
                }
            }
            input.markAsFinished()
            writer?.finishWriting {
                DispatchQueue.main.async {
                    if writer?.status == .completed {
                        completion(.success(outputURL))
                    } else {
                        completion(.failure(writer?.error ?? NSError(domain: "Export failed", code: -2)))
                    }
                }
            }
        }
    }

    func saveVideoToPhotos(url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                completion(false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                completion(success)
            }
        }
    }
}
