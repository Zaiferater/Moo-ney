import Foundation

private var failures = 0
private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        fputs("FAIL [line \(line)]: \(message)\n", stderr)
    }
}

private func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    _ second: Int = 0,
    calendar: Calendar
) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    comps.second = second
    comps.nanosecond = 0
    return calendar.date(from: comps)!
}

private func runPayrollMathTests() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    // May 2026: May 1 is Friday. Weekdays in May 2026 = 21 days.
    let settings = Settings(
        monthlyPay: Decimal(21000),
        startMinutes: 9 * 60,
        endMinutes: 18 * 60
    )

    // Working halfway through Friday May 1, 2026 (13:30 => 4.5h / 9h = 500)
    let midday = makeDate(2026, 5, 1, 13, 30, 0, calendar: cal)
    let snapMidday = PaySnapshot.at(settings: settings, now: midday, calendar: cal)
    expect(snapMidday.status == .working, "Expected working status at 13:30")
    expect(snapMidday.todayPay == Decimal(500), "Expected todayPay 500, got \(snapMidday.todayPay)")
    expect(snapMidday.monthPay == Decimal(500), "Expected monthPay 500, got \(snapMidday.monthPay)")
    expect(PaySnapshot.clock(seconds: Int64(ceil(snapMidday.remainingSeconds))) == "04:30:00", "Expected 04:30:00 remaining")
    expect(!snapMidday.isOnBreak, "Expected not on break before Friday 18:00")
    expect(PaySnapshot.breakClock(remaining: snapMidday.untilBreakSeconds) == "0天4小时30分钟",
           "Expected 0天4小时30分钟 until break, got \(PaySnapshot.breakClock(remaining: snapMidday.untilBreakSeconds))")

    // Before work on Monday May 4, 2026 (completedDays = 1: May 1)
    let beforeWork = makeDate(2026, 5, 4, 8, 30, 0, calendar: cal)
    let snapBefore = PaySnapshot.at(settings: settings, now: beforeWork, calendar: cal)
    expect(snapBefore.status == .beforeWork, "Expected beforeWork at 08:30")
    expect(snapBefore.todayPay == Decimal(0), "Expected todayPay 0 before work")
    expect(snapBefore.monthPay == Decimal(1000), "Expected monthPay 1000 after 1 completed workday, got \(snapBefore.monthPay)")
    // Monday May 4 08:30 to Friday May 8 18:00 = 4 days 9 hours 30 minutes
    expect(PaySnapshot.breakClock(remaining: snapBefore.untilBreakSeconds) == "4天9小时30分钟",
           "Expected 4天9小时30分钟 until break, got \(PaySnapshot.breakClock(remaining: snapBefore.untilBreakSeconds))")

    // After work on Friday May 1, 2026 (18:05) => already on break because Saturday May 2 is off
    let afterWorkFri = makeDate(2026, 5, 1, 18, 5, 0, calendar: cal)
    let snapAfter = PaySnapshot.at(settings: settings, now: afterWorkFri, calendar: cal)
    expect(snapAfter.status == .afterWork, "Expected afterWork at 18:05")
    expect(snapAfter.todayPay == Decimal(1000), "Expected full day pay 1000 after work")
    expect(snapAfter.isOnBreak, "Expected isOnBreak true after Friday end time")

    // Day off on Saturday May 2, 2026
    let sat = makeDate(2026, 5, 2, 10, 0, 0, calendar: cal)
    let snapSat = PaySnapshot.at(settings: settings, now: sat, calendar: cal)
    expect(snapSat.status == .dayOff, "Expected dayOff on Saturday")
    expect(snapSat.todayPay == Decimal(0), "Expected todayPay 0 on day off")
    expect(snapSat.monthPay == Decimal(1000), "Expected monthPay 1000 on Saturday May 2")
    expect(snapSat.isOnBreak, "Expected isOnBreak true on day off")

    // Custom workdays: make Saturday May 2 a workday (补班) => Friday May 1 break extends to Saturday 18:00
    var custom = settings
    custom.useCustomWorkdays = true
    custom.workdayOverrides = [CalendarDay(year: 2026, month: 5, day: 2)]
    let snapCustomFri = PaySnapshot.at(settings: custom, now: midday, calendar: cal)
    // From May 1 13:30 to May 2 18:00 = 1 day 4 hours 30 minutes
    expect(PaySnapshot.breakClock(remaining: snapCustomFri.untilBreakSeconds) == "1天4小时30分钟",
           "Expected 1天4小时30分钟 with Saturday makeup day, got \(PaySnapshot.breakClock(remaining: snapCustomFri.untilBreakSeconds))")

    // Zero workdays in a month => todayPay & monthPay are 0
    var zeroMonth = settings
    zeroMonth.useCustomWorkdays = true
    zeroMonth.workdayOverrides = (1...31).compactMap { d in
        let day = CalendarDay(year: 2026, month: 5, day: d)
        return day.isWeekday ? day : nil
    }
    let snapZero = PaySnapshot.at(settings: zeroMonth, now: midday, calendar: cal)
    expect(snapZero.status == .dayOff, "Expected dayOff when all weekdays disabled")
    expect(snapZero.todayPay == Decimal(0) && snapZero.monthPay == Decimal(0), "Expected zero pay for 0-workday month")
}

private func runValidationTests() {
    expect(Settings.parseMonthlyPay("0") == Decimal(0), "0 should be valid")
    expect(Settings.parseMonthlyPay("12345.67") == Decimal(string: "12345.67"), "2 decimals should be valid")
    expect(Settings.parseMonthlyPay("99999999.99") == Settings.maxMonthlyPay, "max pay should be valid")
    expect(Settings.parseMonthlyPay("100000000") == nil, "above max should be invalid")
    expect(Settings.parseMonthlyPay("-1") == nil, "negative should be invalid")
    expect(Settings.parseMonthlyPay("12.345") == nil, "3 decimals should be invalid")
    expect(Settings.parseMonthlyPay("1,000") == nil, "comma should be invalid")
    expect(Settings.parseMonthlyPay("") == nil, "empty should be invalid")

    expect(PaySnapshot.formatAmount(Decimal(string: "12.3")!) == "¥12.30000", "amount should format to 5 decimals")
}

private func runStoreTests() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mooney-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = SettingsStore(fileURL: tempDir.appendingPathComponent("settings.xml"))

    // 1. Fresh store returns nil without error
    do {
        let (loaded, recovered) = try store.load()
        expect(loaded == nil && !recovered, "Fresh store should return nil")
    } catch {
        expect(false, "Fresh store threw: \(error)")
    }

    // 2. Save & reload roundtrip (including overrides, coordinates, scale & font)
    let original = Settings(
        monthlyPay: Decimal(string: "18500.5")!,
        startMinutes: 9 * 60 + 30,
        endMinutes: 18 * 60 + 30,
        left: 240.5,
        top: 120.25,
        alwaysOnTop: false,
        mascotId: "cat",
        themeId: "smoke",
        windowScale: 1.35,
        fontName: "PingFang SC",
        useCustomWorkdays: true,
        workdayOverrides: [
            CalendarDay(year: 2026, month: 5, day: 2),
            CalendarDay(year: 2026, month: 5, day: 1),
            CalendarDay(year: 2026, month: 5, day: 1)
        ]
    )

    do {
        try store.save(original)
        let (loaded, recovered) = try store.load()
        expect(!recovered, "Normal load should not mark recovered")
        expect(loaded == original, "Roundtrip settings mismatch: \(String(describing: loaded))")
        expect(FileManager.default.fileExists(atPath: store.backupURL.path), "Backup file should exist after first save")
    } catch {
        expect(false, "Save/load threw: \(error)")
    }

    // 2b. Backward-compatible XML without WindowScale/FontName defaults gracefully
    do {
        let legacyXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <Settings>
          <MonthlyPay>12000</MonthlyPay>
          <StartMinutes>540</StartMinutes>
          <EndMinutes>1080</EndMinutes>
          <AlwaysOnTop>true</AlwaysOnTop>
          <MascotId>cow</MascotId>
          <ThemeId>lilac</ThemeId>
          <UseCustomWorkdays>false</UseCustomWorkdays>
          <WorkdayOverrides />
        </Settings>
        """
        let legacyStore = SettingsStore(fileURL: tempDir.appendingPathComponent("legacy.xml"))
        try Data(legacyXML.utf8).write(to: legacyStore.fileURL)
        let (loaded, _) = try legacyStore.load()
        expect(loaded?.windowScale == 1.0, "Legacy XML should default windowScale to 1.0")
        expect(loaded?.fontName == "", "Legacy XML should default fontName to empty string")
    } catch {
        expect(false, "Legacy XML load threw: \(error)")
    }

    // 2c. Out-of-range windowScale fails validation
    var badScale = original
    badScale.windowScale = 0.2
    expect(!badScale.isValid(), "Scale 0.2 should be invalid")
    badScale.windowScale = 3.0
    expect(!badScale.isValid(), "Scale 3.0 should be invalid")
    expect(Settings.clampScale(0.2) == Settings.minWindowScale, "clampScale low bound")
    expect(Settings.clampScale(3.0) == Settings.maxWindowScale, "clampScale high bound")

    // 3. Corrupt primary file => automatic recovery from .bak
    do {
        try Data("not valid xml <<<".utf8).write(to: store.fileURL)
        let (loaded, recovered) = try store.load()
        expect(recovered, "Corrupt primary should recover from backup")
        expect(loaded == original, "Recovered settings should match original")
    } catch {
        expect(false, "Recovery threw: \(error)")
    }

    // 4. Corrupt both primary and backup => throws error
    do {
        try Data("broken".utf8).write(to: store.fileURL)
        try Data("also broken".utf8).write(to: store.backupURL)
        _ = try store.load()
        expect(false, "Both corrupt should throw")
    } catch {
        expect(true, "Expected error when both files are corrupt")
    }
}

@main
struct PayrollTestRunner {
    static func main() {
        runPayrollMathTests()
        runValidationTests()
        runStoreTests()

        if failures == 0 {
            print("All \(checks) checks passed.")
            exit(0)
        } else {
            fputs("\(failures) of \(checks) checks failed.\n", stderr)
            exit(1)
        }
    }
}
