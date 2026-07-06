// Defaults preserve today's behavior: pill on, 5-hour on, 7-day off.
nonisolated enum UsageDisplaySettings {
    static let showUsageKey = "usageShowInStatusBar"
    static let showFiveHourKey = "usageShowFiveHour"
    static let showSevenDayKey = "usageShowSevenDay"

    static let showUsageDefault = true
    static let showFiveHourDefault = true
    static let showSevenDayDefault = false
}
