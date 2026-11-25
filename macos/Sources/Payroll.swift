import Foundation

struct CalendarDay: Comparable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    private static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    static func today(in calendar: Calendar = .current) -> CalendarDay {
        return from(Date(), in: calendar)
    }

    static func from(_ date: Date, in calendar: Calendar = .current) -> CalendarDay {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    static func parse(_ isoString: String) -> CalendarDay? {
        let trimmed = isoString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              y >= 1, y <= 9999, m >= 1, m <= 12,
              d >= 1, d <= daysInMonth(year: y, month: m) else {
            return nil
        }
        return CalendarDay(year: y, month: m, day: d)
    }

    var isoString: String {
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    var chineseLabel: String {
        return "\(year)年\(month)月\(day)日"
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let cal = gregorian
        guard let date = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: date) else {
            return 30
        }
        return range.count
    }

    /// 0 = Monday ... 6 = Sunday
    var mondayBasedWeekday: Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        let cal = Self.gregorian
        guard let date = cal.date(from: comps) else { return 0 }
        let weekday = cal.component(.weekday, from: date) // 1 = Sun, 2 = Mon, ..., 7 = Sat
        return (weekday + 5) % 7
    }

    var isWeekday: Bool {
        let w = mondayBasedWeekday
        return w < 5
    }

    func addingDays(_ offset: Int) -> CalendarDay? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        let cal = Self.gregorian
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .day, value: offset, to: base) else {
            return nil
        }
        let result = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let y = result.year, let m = result.month, let d = result.day,
              y >= 1, y <= 9999 else {
            return nil
        }
        return CalendarDay(year: y, month: m, day: d)
    }

    func addingMonths(_ offset: Int) -> CalendarDay? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let cal = Self.gregorian
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .month, value: offset, to: base) else {
            return nil
        }
        let result = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let y = result.year, let m = result.month, let d = result.day,
              y >= 1, y <= 9999 else {
            return nil
        }
        return CalendarDay(year: y, month: m, day: d)
    }

    func date(minutesFromMidnight: Int = 0, in calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        comps.second = 0
        comps.nanosecond = 0
        return calendar.date(from: comps)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

struct Settings: Equatable {
    static let defaultMascotId = "cow"
    static let defaultThemeId = "lilac"
    static let defaultWindowScale: Double = 1.0
    static let minWindowScale: Double = 0.7
    static let maxWindowScale: Double = 2.0
    static let defaultFontName = ""
    static let maxMonthlyPay = Decimal(string: "99999999.99", locale: Locale(identifier: "en_US_POSIX"))!

    var monthlyPay: Decimal
    var startMinutes: Int
    var endMinutes: Int
    var left: Double?
    var top: Double?
    var alwaysOnTop: Bool
    var mascotId: String
    var themeId: String
    var windowScale: Double
    var fontName: String
    var useCustomWorkdays: Bool
    var workdayOverrides: [CalendarDay] {
        didSet {
            let normalized = Array(Set(workdayOverrides)).sorted()
            if normalized != workdayOverrides {
                workdayOverrides = normalized
            }
        }
    }

    init(
        monthlyPay: Decimal = -1,
        startMinutes: Int = -1,
        endMinutes: Int = 0,
        left: Double? = nil,
        top: Double? = nil,
        alwaysOnTop: Bool = true,
        mascotId: String = Settings.defaultMascotId,
        themeId: String = Settings.defaultThemeId,
        windowScale: Double = Settings.defaultWindowScale,
        fontName: String = Settings.defaultFontName,
        useCustomWorkdays: Bool = false,
        workdayOverrides: [CalendarDay] = []
    ) {
        self.monthlyPay = monthlyPay
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.left = left
        self.top = top
        self.alwaysOnTop = alwaysOnTop
        self.mascotId = mascotId
        self.themeId = themeId
        self.windowScale = windowScale
        self.fontName = fontName
        self.useCustomWorkdays = useCustomWorkdays
        self.workdayOverrides = Array(Set(workdayOverrides)).sorted()
    }

    static func clampScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return defaultWindowScale }
        return min(maxWindowScale, max(minWindowScale, (scale * 100.0).rounded() / 100.0))
    }

    func isWorkday(_ day: CalendarDay) -> Bool {
        let weekday = day.isWeekday
        if useCustomWorkdays && containsOverride(day) {
            return !weekday
        }
        return weekday
    }

    private func containsOverride(_ day: CalendarDay) -> Bool {
        var low = 0
        var high = workdayOverrides.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            let current = workdayOverrides[mid]
            if current == day {
                return true
            } else if current < day {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return false
    }

    func isValid() -> Bool {
        if monthlyPay.isNaN || monthlyPay < 0 || monthlyPay > Settings.maxMonthlyPay {
            return false
        }
        var rounded = Decimal()
        var value = monthlyPay
        NSDecimalRound(&rounded, &value, 2, .plain)
        if rounded != monthlyPay {
            return false
        }
        if startMinutes < 0 || endMinutes >= 24 * 60 || endMinutes <= startMinutes {
            return false
        }
        if let l = left, !l.isFinite {
            return false
        }
        if let t = top, !t.isFinite {
            return false
        }
        if !windowScale.isFinite || windowScale < Settings.minWindowScale || windowScale > Settings.maxWindowScale {
            return false
        }
        return true
    }

    /// Strict parser matching Windows `NumberStyles.AllowDecimalPoint` with `CultureInfo.InvariantCulture`.
    static func parseMonthlyPay(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var seenDot = false
        var digitsBeforeDot = 0
        var digitsAfterDot = 0
        for scalar in trimmed.unicodeScalars {
            if scalar >= "0" && scalar <= "9" {
                if seenDot {
                    digitsAfterDot += 1
                    if digitsAfterDot > 2 { return nil }
                } else {
                    digitsBeforeDot += 1
                }
            } else if scalar == "." {
                if seenDot { return nil }
                seenDot = true
            } else {
                return nil
            }
        }
        guard digitsBeforeDot > 0 || digitsAfterDot > 0 else { return nil }
        guard let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0, value <= maxMonthlyPay else {
            return nil
        }
        var rounded = Decimal()
        var mutableValue = value
        NSDecimalRound(&rounded, &mutableValue, 2, .plain)
        guard rounded == value else { return nil }
        return value
    }

    static func formatMonthlyPayInput(_ pay: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: pay)) ?? "0"
    }
}

enum SettingsStoreError: Error {
    case invalidData(String)
    case ioFailure(Error)
}

final class SettingsStore {
    let fileURL: URL
    let backupURL: URL

    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = appSupport.appendingPathComponent("WorkdayTimer", isDirectory: true)
        self.init(fileURL: dir.appendingPathComponent("settings.xml"))
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.backupURL = URL(fileURLWithPath: fileURL.path + ".bak")
    }

    func load() throws -> (settings: Settings?, recovered: Bool) {
        let (primary, primaryError) = read(from: fileURL)
        let (backup, backupError) = read(from: backupURL)

        if let primary {
            if backup == nil {
                try? createBackup(from: fileURL)
            }
            return (primary, false)
        }

        guard let backup else {
            if let error = primaryError ?? backupError {
                throw error
            }
            return (nil, false)
        }

        try? save(backup)
        return (backup, true)
    }

    func save(_ settings: Settings) throws {
        guard settings.isValid() else {
            throw SettingsStoreError.invalidData("Invalid settings values.")
        }
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw SettingsStoreError.ioFailure(error)
        }

        let xmlData = serialize(settings)
        let tempURL = URL(fileURLWithPath: fileURL.path + "." + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try writeAndSync(xmlData, to: tempURL)
            let (existingPrimary, _) = read(from: fileURL)
            let (existingBackup, _) = read(from: backupURL)
            if existingPrimary != nil {
                try createBackup(from: fileURL)
            } else if existingBackup == nil {
                try createBackup(from: tempURL)
            }
            try atomicReplace(temporaryURL: tempURL, destinationURL: fileURL)
        } catch let error as SettingsStoreError {
            throw error
        } catch {
            throw SettingsStoreError.ioFailure(error)
        }
    }

    private func createBackup(from sourceURL: URL) throws {
        let tempURL = URL(fileURLWithPath: backupURL.path + "." + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        let data = try Data(contentsOf: sourceURL)
        try writeAndSync(data, to: tempURL)
        try atomicReplace(temporaryURL: tempURL, destinationURL: backupURL)
    }

    private func writeAndSync(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw SettingsStoreError.ioFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
        defer { close(fd) }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        if fsync(fd) != 0 {
            throw SettingsStoreError.ioFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
    }

    private func atomicReplace(temporaryURL: URL, destinationURL: URL) throws {
        if rename(temporaryURL.path, destinationURL.path) != 0 {
            throw SettingsStoreError.ioFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
    }

    private func read(from url: URL) -> (Settings?, Error?) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            return (nil, nil)
        } catch {
            return (nil, SettingsStoreError.ioFailure(error))
        }

        let delegate = SettingsXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let settings = delegate.result, settings.isValid() else {
            return (nil, SettingsStoreError.invalidData("Invalid settings XML."))
        }
        return (settings, nil)
    }

    private func serialize(_ settings: Settings) -> Data {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<Settings xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">")
        lines.append("  <MonthlyPay>\(Settings.formatMonthlyPayInput(settings.monthlyPay))</MonthlyPay>")
        lines.append("  <StartMinutes>\(settings.startMinutes)</StartMinutes>")
        lines.append("  <EndMinutes>\(settings.endMinutes)</EndMinutes>")
        if let left = settings.left {
            lines.append("  <Left>\(formatDouble(left))</Left>")
        } else {
            lines.append("  <Left xsi:nil=\"true\" />")
        }
        if let top = settings.top {
            lines.append("  <Top>\(formatDouble(top))</Top>")
        } else {
            lines.append("  <Top xsi:nil=\"true\" />")
        }
        lines.append("  <AlwaysOnTop>\(settings.alwaysOnTop ? "true" : "false")</AlwaysOnTop>")
        lines.append("  <MascotId>\(escapeXML(settings.mascotId))</MascotId>")
        lines.append("  <ThemeId>\(escapeXML(settings.themeId))</ThemeId>")
        lines.append("  <WindowScale>\(formatDouble(settings.windowScale))</WindowScale>")
        lines.append("  <FontName>\(escapeXML(settings.fontName))</FontName>")
        lines.append("  <UseCustomWorkdays>\(settings.useCustomWorkdays ? "true" : "false")</UseCustomWorkdays>")
        if settings.workdayOverrides.isEmpty {
            lines.append("  <WorkdayOverrides />")
        } else {
            lines.append("  <WorkdayOverrides>")
            for day in settings.workdayOverrides {
                lines.append("    <Date>\(day.isoString)</Date>")
            }
            lines.append("  </WorkdayOverrides>")
        }
        lines.append("</Settings>")
        lines.append("")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func formatDouble(_ value: Double) -> String {
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func escapeXML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }
}

private final class SettingsXMLParserDelegate: NSObject, XMLParserDelegate {
    private var settings = Settings()
    private var sawRoot = false
    private var inOverrides = false
    private var currentElement = ""
    private var currentIsNil = false
    private var buffer = ""
    private var overrides: [CalendarDay] = []
    private var failed = false

    var result: Settings? {
        guard sawRoot, !failed else { return nil }
        var finalSettings = settings
        finalSettings.workdayOverrides = overrides
        return finalSettings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "Settings" {
            sawRoot = true
        } else if elementName == "WorkdayOverrides" {
            inOverrides = true
        }
        currentElement = elementName
        currentIsNil = (attributeDict["xsi:nil"]?.lowercased() == "true")
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if inOverrides && elementName == "Date" {
            if let day = CalendarDay.parse(text) {
                overrides.append(day)
            } else {
                failed = true
            }
        } else if elementName == "WorkdayOverrides" {
            inOverrides = false
        } else {
            switch elementName {
            case "MonthlyPay":
                if let val = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !val.isNaN {
                    settings.monthlyPay = val
                } else {
                    failed = true
                }
            case "StartMinutes":
                if let val = Int(text) {
                    settings.startMinutes = val
                } else {
                    failed = true
                }
            case "EndMinutes":
                if let val = Int(text) {
                    settings.endMinutes = val
                } else {
                    failed = true
                }
            case "Left":
                if currentIsNil || text.isEmpty {
                    settings.left = nil
                } else if let val = Double(text) {
                    settings.left = val
                } else {
                    failed = true
                }
            case "Top":
                if currentIsNil || text.isEmpty {
                    settings.top = nil
                } else if let val = Double(text) {
                    settings.top = val
                } else {
                    failed = true
                }
            case "AlwaysOnTop":
                if let val = parseBool(text) {
                    settings.alwaysOnTop = val
                } else {
                    failed = true
                }
            case "MascotId":
                settings.mascotId = text.isEmpty ? Settings.defaultMascotId : text
            case "ThemeId":
                settings.themeId = text.isEmpty ? Settings.defaultThemeId : text
            case "WindowScale":
                if let val = Double(text), val.isFinite {
                    settings.windowScale = val
                } else {
                    failed = true
                }
            case "FontName":
                settings.fontName = text
            case "UseCustomWorkdays":
                if let val = parseBool(text) {
                    settings.useCustomWorkdays = val
                } else {
                    failed = true
                }
            default:
                break
            }
        }
        currentElement = ""
        buffer = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }

    private func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }
}

enum WorkStatus: Equatable {
    case beforeWork
    case working
    case afterWork
    case dayOff
}

struct PaySnapshot: Equatable {
    let todayPay: Decimal
    let monthPay: Decimal
    let workedSeconds: TimeInterval
    let remainingSeconds: TimeInterval
    let status: WorkStatus
    let untilBreakSeconds: TimeInterval
    let isOnBreak: Bool

    static func at(settings: Settings, now: Date, calendar: Calendar = .current) -> PaySnapshot {
        let today = CalendarDay.from(now, in: calendar)
        let daysInMonth = CalendarDay.daysInMonth(year: today.year, month: today.month)
        var workdays = 0
        var completedDays = 0
        for dayNum in 1...daysInMonth {
            let candidate = CalendarDay(year: today.year, month: today.month, day: dayNum)
            guard settings.isWorkday(candidate) else { continue }
            workdays += 1
            if dayNum < today.day {
                completedDays += 1
            }
        }

        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let timeOfDaySeconds =
            Double(comps.hour ?? 0) * 3600.0 +
            Double(comps.minute ?? 0) * 60.0 +
            Double(comps.second ?? 0) +
            Double(comps.nanosecond ?? 0) / 1_000_000_000.0

        let startSeconds = Double(settings.startMinutes * 60)
        let endSeconds = Double(settings.endMinutes * 60)
        let durationSeconds = endSeconds - startSeconds

        let status: WorkStatus
        let workedSeconds: TimeInterval
        let remainingSeconds: TimeInterval

        if !settings.isWorkday(today) {
            status = .dayOff
            workedSeconds = 0
            remainingSeconds = 0
        } else if timeOfDaySeconds < startSeconds {
            status = .beforeWork
            workedSeconds = 0
            remainingSeconds = 0
        } else if timeOfDaySeconds >= endSeconds {
            status = .afterWork
            workedSeconds = durationSeconds
            remainingSeconds = 0
        } else {
            status = .working
            workedSeconds = timeOfDaySeconds - startSeconds
            remainingSeconds = endSeconds - timeOfDaySeconds
        }

        var isOnBreak = (status == .dayOff)
        var untilBreakSeconds: TimeInterval = 0
        if !isOnBreak {
            var lastWorkday = today
            var steps = 0
            while steps < 3660, let next = lastWorkday.addingDays(1), settings.isWorkday(next) {
                lastWorkday = next
                steps += 1
            }
            if let breakStart = lastWorkday.date(minutesFromMidnight: settings.endMinutes, in: calendar) {
                let delta = breakStart.timeIntervalSince(now)
                if delta <= 0 {
                    isOnBreak = true
                } else {
                    untilBreakSeconds = delta
                }
            } else {
                isOnBreak = true
            }
        }

        if workdays == 0 || durationSeconds <= 0 {
            return PaySnapshot(
                todayPay: 0,
                monthPay: 0,
                workedSeconds: workedSeconds,
                remainingSeconds: remainingSeconds,
                status: status,
                untilBreakSeconds: untilBreakSeconds,
                isOnBreak: isOnBreak
            )
        }

        // Convert to 100-nanosecond ticks to mirror C# TimeSpan.Ticks precision
        let ticksPerSecond: Int64 = 10_000_000
        let workedTicks = Decimal(Int64((workedSeconds * Double(ticksPerSecond)).rounded()))
        let durationTicks = Decimal(Int64(settings.endMinutes - settings.startMinutes) * 60 * ticksPerSecond)
        let monthTicks = durationTicks * Decimal(workdays)

        let todayPay = settings.monthlyPay * workedTicks / monthTicks
        let monthPay = settings.monthlyPay * (Decimal(completedDays) * durationTicks + workedTicks) / monthTicks

        return PaySnapshot(
            todayPay: todayPay,
            monthPay: monthPay,
            workedSeconds: workedSeconds,
            remainingSeconds: remainingSeconds,
            status: status,
            untilBreakSeconds: untilBreakSeconds,
            isOnBreak: isOnBreak
        )
    }

    static func clock(seconds: Int64) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02lld:%02lld:%02lld", hours, minutes, secs)
    }

    static func breakClock(remaining: TimeInterval) -> String {
        let totalMinutes = max(0, Int64(ceil(remaining / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        return "\(days)天\(hours)小时\(minutes)分钟"
    }

    static func formatAmount(_ amount: Decimal) -> String {
        var rounded = Decimal()
        var value = amount
        NSDecimalRound(&rounded, &value, 5, .bankers)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 5
        formatter.maximumFractionDigits = 5
        let text = formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0.00000"
        return "¥" + text
    }
}
