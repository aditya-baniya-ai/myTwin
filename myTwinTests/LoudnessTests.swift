import AVFoundation
import XCTest
@testable import myTwin

/// The recording bar's dots: silence stays flat, speech lifts them.
final class LoudnessTests: XCTestCase {
    private func buffer(amplitude: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buffer.frameLength = 1600
        for index in 0..<1600 {
            buffer.floatChannelData![0][index] = amplitude * sin(Float(index) * 2 * .pi * 220 / 16_000)
        }
        return buffer
    }

    func testSilenceIsZero() {
        XCTAssertEqual(loudness(of: buffer(amplitude: 0)), 0)
    }

    func testRoomNoiseStaysBelowTheSpeechThreshold() {
        XCTAssertLessThan(loudness(of: buffer(amplitude: 0.003)), 0.15, "the bar turns white above 0.15")
    }

    func testSpeechIsWellAboveIt() {
        XCTAssertGreaterThan(loudness(of: buffer(amplitude: 0.1)), 0.5)
    }

    func testLouderNeverExceedsOne() {
        XCTAssertEqual(loudness(of: buffer(amplitude: 1)), 1)
    }
}
