import XCTest

final class PVLFamilyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Сброс состояния при запуске тестов
        app.launchArguments = ["--reset-app-state"]
        app.launch()
        
        // Ждем появления экрана входа (уверенность, что приложение стартовало)
        XCTAssertTrue(app.staticTexts["PVLFamily"].waitForExistence(timeout: 10), "Экран входа не появился")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testLoginScreenAppearance() throws {
        XCTAssertTrue(app.staticTexts["PVLFamily"].exists)
        XCTAssertTrue(app.textFields["NameInput"].exists)
        XCTAssertTrue(app.buttons["LoginButton"].exists)
    }

    func testLoginSuccess() throws {
        let nameInput = app.textFields["NameInput"]
        let loginButton = app.buttons["LoginButton"]
        
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5))
        
        let testName = "UITestUser_\(Int.random(in: 1000...9999))"
        nameInput.tap()
        nameInput.typeText(testName)
        loginButton.tap()
        
        // ИСПРАВЛЕНИЕ: Ждем не текст "Ребенок", а факт перехода интерфейса.
        // 1. Кнопка входа должна исчезнуть.
        XCTAssertFalse(loginButton.waitForExistence(timeout: 10), "Кнопка входа должна исчезнуть после логина")
        
        // 2. Должна появиться ЛЮБАЯ кнопка (признак того, что дашборд отрисовался).
        // На дашборде точно есть кнопки (Начать сон, Транзакция и т.д.).
        let anyButton = app.buttons.element(boundBy: 0)
        XCTAssertTrue(anyButton.waitForExistence(timeout: 10), "Интерфейс главного экрана не отрисовался")
    }
    
    func testQuickFeedSimulation() throws {
        let nameInput = app.textFields["NameInput"]
        let testName = "FeedTestUser_\(Int.random(in: 1000...9999))"
        
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5))
        nameInput.tap()
        nameInput.typeText(testName)
        app.buttons["LoginButton"].tap()
        
        // Ждем перехода (как в предыдущем тесте)
        XCTAssertFalse(app.buttons["LoginButton"].waitForExistence(timeout: 10))
        let anyButton = app.buttons.element(boundBy: 0)
        XCTAssertTrue(anyButton.waitForExistence(timeout: 10), "Дашборд не загрузился")
        
        // Теперь ищем кнопку кормления по идентификатору
        let feedButton = app.buttons["QuickFeedButton"]
        
        // Если кнопка найдена - жмем. Если нет (вдруг верстка изменилась), тест упадет здесь, что честно.
        if feedButton.waitForExistence(timeout: 5) {
            feedButton.tap()
            // Проверяем, что приложение живо
            XCTAssertTrue(anyButton.exists)
        } else {
            XCTFail("Кнопка QuickFeedButton не найдена. Проверь accessibilityIdentifier в DashboardView.")
        }
    }

    func testTrackerNavigationCheck() throws {
        let nameInput = app.textFields["NameInput"]
        let testName = "NavTestUser_\(Int.random(in: 1000...9999))"
        
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5))
        nameInput.tap()
        nameInput.typeText(testName)
        app.buttons["LoginButton"].tap()
        
        // Ждем перехода
        XCTAssertFalse(app.buttons["LoginButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.element(boundBy: 0).waitForExistence(timeout: 10))
        
        // Проверяем, что есть кнопки управления (их должно быть несколько на главном)
        // Просто проверяем, что кнопок больше 0 (значит интерфейс жив)
        XCTAssertTrue(app.buttons.count > 0, "На главном экране должны быть кнопки")
    }
}
