import Foundation

class SchedulePreferences {
    static let shared = SchedulePreferences()

    private let enabledDaysKey = "enabledDays"
    private let enabledHoursKey = "enabledHours"

    // Weekday numbers follow Calendar: 1=Sunday ... 7=Saturday
    private let defaultEnabledDays: Set<Int> = [2,3,4,5,6] // Mon-Fri
    private let defaultEnabledHours: Set<Int> = [8,9,10,11,12,13,15,16,17,18]

    private init() {}

    var enabledDays: Set<Int> {
        get {
            if let stored = UserDefaults.standard.array(forKey: enabledDaysKey) as? [Int] {
                return Set(stored)
            }
            return defaultEnabledDays
        }
        set {
            let array = Array(newValue).sorted()
            UserDefaults.standard.set(array, forKey: enabledDaysKey)
        }
    }

    var enabledHours: Set<Int> {
        get {
            if let stored = UserDefaults.standard.array(forKey: enabledHoursKey) as? [Int] {
                return Set(stored)
            }
            return defaultEnabledHours
        }
        set {
            let array = Array(newValue).sorted()
            UserDefaults.standard.set(array, forKey: enabledHoursKey)
        }
    }

    func isDayEnabled(_ weekday: Int) -> Bool {
        enabledDays.contains(weekday)
    }

    func toggleDay(_ weekday: Int) {
        var days = enabledDays
        if days.contains(weekday) {
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
        enabledDays = days
    }

    func isHourEnabled(_ hour: Int) -> Bool {
        enabledHours.contains(hour)
    }

    func toggleHour(_ hour: Int) {
        var hours = enabledHours
        if hours.contains(hour) {
            hours.remove(hour)
        } else {
            hours.insert(hour)
        }
        enabledHours = hours
    }
}

