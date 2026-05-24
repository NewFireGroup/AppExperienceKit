import Foundation

public enum ReleaseControlKey: String, CaseIterable, Sendable, Equatable {
    case planning
    case planningEditor = "planning_editor"
    case feedbackFeature = "feedback_feature"
    case authenticationFeature = "authentication_feature"
    case cashflowCalendarYearFeature = "cashflow_calendar_year_feature"

    public var displayName: String {
        switch self {
        case .planning:
            return "Planning"
        case .planningEditor:
            return "Planning Editor"
        case .feedbackFeature:
            return "Feedback"
        case .authenticationFeature:
            return "Authentication"
        case .cashflowCalendarYearFeature:
            return "Calendar-Year Cashflow"
        }
    }

    public var usesFutureFeatureSuffix: Bool {
        rawValue.hasSuffix("_feature")
    }
}
