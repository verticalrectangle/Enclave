//  EnclaveActivity.swift  (shared: app + EnclaveWidgets extension)
//  The Live Activity contract. ContentState is the live session snapshot the app
//  pushes to the lock screen / Dynamic Island as omp frames arrive.

import ActivityKit
import Foundation

struct EnclaveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String        // session / repo name
        var action: String       // STREAMING · WAITING · ANSWER · LIVE · ENDED
        var phase: String        // connecting / waiting / live / ended
        var working: Bool        // agent is streaming
        var waiting: Bool        // a host ask is pending your answer
        var tokens: String       // context tokens label
        var model: String
    }

    var sessionId: String
}
