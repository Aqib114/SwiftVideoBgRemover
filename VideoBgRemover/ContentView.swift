//
//  ContentView.swift
//  VideoBgRemover
//
//  Created by Mapple.pk on 08/07/2025.
//

import SwiftUI
import AVFoundation
import _AVKit_SwiftUI

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var isProcessing = false
    @State private var exportProgress: Double = 0
    @State private var showVideoPicker = false
    let viewModel = VideoProcessingViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Video Background Remover")
                    .font(.title2).fontWeight(.semibold)
                
                videoPlayerSection
                actionButtons
                Spacer()
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(videoURL: $videoURL)
            }
            .onChange(of: videoURL) {
                if let newURL = videoURL {
                    player = AVPlayer(url: newURL)
                }
            }

        }
    }

    private var videoPlayerSection: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 250)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 250)
                    .padding(.horizontal)
                    .overlay(Text("No Video Selected").foregroundColor(.gray))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 16) {
            Button {
                showVideoPicker = true
            } label: {
                Label("Select Video", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            Button {
                processAndExport()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView().padding(.trailing, 8)
                    }
                    Text(isProcessing ? "Processing..." : "Remove Background")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isProcessing ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(videoURL == nil || isProcessing)

            if isProcessing {
                ProgressView(value: exportProgress)
                    .padding(.horizontal)
            }
        }
    }

    private func processAndExport() {
        guard let videoURL = videoURL else { return }
        isProcessing = true

        Task {
            guard let fps = await viewModel.getVideoFrameRate(from: videoURL) else {
                isProcessing = false
                return
            }

            viewModel.extractFrames(from: videoURL, frameRate: Int(round(fps))) {  result in
//                guard let self = self else { return }
                switch result {
                case .success(let frames):
                    self.viewModel.removeBackgrounds(from: frames) { result in
                        switch result {
                        case .success(let processedFrames):
                            self.viewModel.createVideo(from: processedFrames, progress: { progress in
                                self.exportProgress = progress
                            }) { result in
                                switch result {
                                case .success(let url):
                                    self.viewModel.saveVideoToPhotos(url: url) { success in
                                        print(success ? "Video saved!" : "Failed to save.")
                                        self.isProcessing = false
                                    }
                                case .failure(let error):
                                    print("Export failed: \(error.localizedDescription)")
                                    self.isProcessing = false
                                }
                            }
                        case .failure(let error):
                            print("Background removal failed: \(error.localizedDescription)")
                            self.isProcessing = false
                        }
                    }
                case .failure(let error):
                    print("Frame extraction failed: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }

}


#Preview {
    ContentView()
}
