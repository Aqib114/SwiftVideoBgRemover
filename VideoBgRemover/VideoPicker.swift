//
//  VideoPicker.swift
//  VideoBgRemover
//
//  Created by Mapple.pk on 10/07/2025.
//

import SwiftUI
import UIKit

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: VideoPicker
        init(_ parent: VideoPicker) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.videoURL = info[.mediaURL] as? URL
            picker.dismiss(animated: true)
        }
    }
}
