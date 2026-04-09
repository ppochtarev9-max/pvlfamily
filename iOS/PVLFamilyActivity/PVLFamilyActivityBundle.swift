import WidgetKit
import SwiftUI

@main
struct PVLFamilyActivityBundle: WidgetBundle {
    var body: some Widget {
        // Здесь мы регистрируем наш виджет Live Activity
        PVLFamilyLiveActivity()
        
        // Если бы были обычные виджеты, их тоже можно добавить через запятую
    }
}
