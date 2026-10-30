// N1 spike 4: can the system media stack open, play and extract frames from a file?
// Build: swiftc -O probe.swift -o probe     Run: probe file1 file2 ...
// Reports AVFoundation's own answers. It does not decide anything about macOS 15:
// run it on a macOS 15 machine to observe that release.
import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

func fourCC(_ value: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xff) }, encoding: .macOSRoman) ?? "?"
}

let version = ProcessInfo.processInfo.operatingSystemVersionString
var rows: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    var row: [String: Any] = ["file": url.lastPathComponent]
    do {
        let (playable, readable, tracks) = try await asset.load(.isPlayable, .isReadable, .tracks)
        row["isPlayable"] = playable
        row["isReadable"] = readable
        var codecs: [String] = []
        for track in tracks {
            for description in try await track.load(.formatDescriptions) { codecs.append(fourCC(CMFormatDescriptionGetMediaSubType(description))) }
        }
        row["trackCodecs"] = codecs
        if let video = tracks.first(where: { $0.mediaType == .video }) {
            row["videoDuration"] = try await asset.load(.duration).seconds
            _ = video
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let (image, actual) = try await generator.image(at: CMTime(seconds: 1.0, preferredTimescale: 600))
                row["frameAt1s"] = "\(image.width)x\(image.height) @\(actual.seconds)"
            } catch { row["frameAt1s"] = "failed: \((error as NSError).localizedDescription)" }
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            let deadline = Date().addingTimeInterval(4)
            while item.status == .unknown && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            row["playerItemStatus"] = item.status == .readyToPlay ? "readyToPlay" : item.status == .failed ? "failed: \(item.error?.localizedDescription ?? "?")" : "unknown"
        }
    } catch { row["error"] = (error as NSError).localizedDescription }
    rows.append(row)
}
var decoders: [String: Bool] = [:]
for (name, codec) in [("vp9",kCMVideoCodecType_VP9), ("h264", kCMVideoCodecType_H264), ("hevc", kCMVideoCodecType_HEVC), ("av1", kCMVideoCodecType_AV1)] {
    decoders[name] = VTIsHardwareDecodeSupported(codec)
}
let report: [String: Any] = ["os": version, "hardwareDecode": decoders, "files": rows]
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
