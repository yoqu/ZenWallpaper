import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("baseUrl") var baseUrl: String = "https://api.openai.com/v1"
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("model") var model: String = "gpt-image-2"
    @AppStorage("useDate") var useDate: Bool = true
    @AppStorage("useLunar") var useLunar: Bool = true
    @AppStorage("autoFreqRaw") var autoFreqRaw: String = AutoFreq.daily.rawValue
    @AppStorage("multiDisplay") var multiDisplay: String = "unified"
    @AppStorage("cacheLimit") var cacheLimit: Int = 12
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("historyLayoutRaw") var historyLayoutRaw: String = HistoryLayout.rail.rawValue

    var autoFreq: AutoFreq {
        get { AutoFreq(rawValue: autoFreqRaw) ?? .daily }
        set { autoFreqRaw = newValue.rawValue }
    }
    var historyLayout: HistoryLayout {
        get { HistoryLayout(rawValue: historyLayoutRaw) ?? .rail }
        set { historyLayoutRaw = newValue.rawValue }
    }
}
