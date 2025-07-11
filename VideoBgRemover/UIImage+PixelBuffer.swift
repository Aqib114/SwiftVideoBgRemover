//
//  UIImage+PixelBuffer.swift
//  VideoBgRemover
//
//  Created by Mapple.pk on 10/07/2025.
//

import Foundation
import UIKit
import CoreVideo

extension UIImage {
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height)) // Explicit clear
        context?.translateBy(x: 0, y: size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
}



extension CIImage {
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs,
                                         &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }
        
        let ciContext = CIContext()
        ciContext.render(self, to: pixelBuffer)
        return pixelBuffer
    }
}
