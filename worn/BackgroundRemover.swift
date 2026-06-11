//
//  BackgroundRemover.swift
//  worn
//

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BackgroundRemover {
    
    /// Removes the background from an image, leaving the subject on transparent.
    /// Returns nil if no subject is detected.
    static func removeBackground(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Step 1: Ask Vision to find the foreground subject(s) in the image
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
            return nil
        }
        
        guard let result = request.results?.first else {
            print("No subject detected")
            return nil
        }
        
        // Step 2: Generate a mask of just the foreground
        do {
            let maskPixelBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )
            
            // Step 3: Apply the mask to the original image
            let originalCIImage = CIImage(cgImage: cgImage)
            let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            
            let filter = CIFilter.blendWithMask()
            filter.inputImage = originalCIImage
            filter.maskImage = maskCIImage
            filter.backgroundImage = CIImage(color: .clear).cropped(to: originalCIImage.extent)
            
            guard let outputImage = filter.outputImage else { return nil }
            
            let context = CIContext()
            guard let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }
            
            return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            print("Mask generation failed: \(error)")
            return nil
        }
    }
}//
//  BackgroundRemover.swift
//  worn
//
//  Created by min rungsinaporn on 1/6/2569 BE.
//

