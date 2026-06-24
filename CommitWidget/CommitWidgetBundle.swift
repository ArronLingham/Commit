import WidgetKit
import SwiftUI

@main
struct CommitWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContributionWidget()
        TodayWidget()
    }
}
