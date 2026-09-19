import AppKit

// Запуск в обход SwiftUI-сцен: приложение собирается без Xcode, а классический
// путь AppKit ведёт себя предсказуемо в самодельном бандле — окно создаётся
// явно, и каждый шаг виден в журнале.

Diagnostics.bootstrap()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)

Diagnostics.log("запускаю цикл событий")
application.run()
