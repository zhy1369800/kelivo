import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Kelivo", category: "BackgroundAudioKeepAlive")

/// 在快捷指令后台执行 AI Agent 任务时，通过播放静音音频让系统维持后台活跃，
/// 防止任务因超过 iOS 的 30 秒后台时间限制而被挂起或杀死。
@MainActor
final class BackgroundAudioKeepAlive: NSObject, AVAudioPlayerDelegate {
    static let shared = BackgroundAudioKeepAlive()

    private var player: AVAudioPlayer?
    private var activeCounter = 0

    private override init() {
        super.init()
    }

    /// 开始后台音频保活
    func start() {
        activeCounter += 1
        guard activeCounter == 1 else {
            logger.info("Background keep-alive already active, count: \(self.activeCounter)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if player == nil {
                player = createSilentAudioPlayer()
            }

            player?.numberOfLoops = -1 // 无限循环
            player?.volume = 0.001 // 极低音量或静音
            player?.play()
            logger.info("Background keep-alive started successfully")
        } catch {
            logger.error("Failed to start background keep-alive: \(error.localizedDescription)")
        }
    }

    /// 停止后台音频保活
    func stop() {
        guard activeCounter > 0 else { return }
        activeCounter -= 1

        if activeCounter == 0 {
            player?.stop()
            player = nil
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                logger.info("Background keep-alive stopped")
            } catch {
                logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
            }
        }
    }

    /// 创建一个微型的 0 振幅静音 WAV 音频数据
    private func createSilentAudioPlayer() -> AVAudioPlayer? {
        let sampleRate: Double = 44100.0
        let duration: Double = 1.0 // 1 秒无声 WAV
        let numSamples = Int(sampleRate * duration)
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let byteRate = Int(sampleRate * Double(numChannels * bitsPerSample / 8))
        let blockAlign = numChannels * bitsPerSample / 8
        let subchunk2Size = numSamples * blockAlign
        let chunkSize = 36 + subchunk2Size

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        var chunkSizeBytes = UInt32(chunkSize).littleEndian
        data.append(Data(bytes: &chunkSizeBytes, count: 4))
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = UInt16(numChannels).littleEndian
        data.append(Data(bytes: &channels, count: 2))
        var sampleRateVal = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sampleRateVal, count: 4))
        var byteRateVal = UInt32(byteRate).littleEndian
        data.append(Data(bytes: &byteRateVal, count: 4))
        var blockAlignVal = UInt16(blockAlign).littleEndian
        data.append(Data(bytes: &blockAlignVal, count: 2))
        var bitsPerSampleVal = UInt16(bitsPerSample).littleEndian
        data.append(Data(bytes: &bitsPerSampleVal, count: 2))

        // data subchunk (全 0 静音)
        data.append(contentsOf: "data".utf8)
        var subchunk2SizeBytes = UInt32(subchunk2Size).littleEndian
        data.append(Data(bytes: &subchunk2SizeBytes, count: 4))
        data.append(Data(repeating: 0, count: subchunk2Size))

        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            return p
        } catch {
            logger.error("Error creating silent audio player: \(error.localizedDescription)")
            return nil
        }
    }
}
