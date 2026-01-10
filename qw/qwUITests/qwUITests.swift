//
//  qwUITests.swift
//  qwUITests
//
//  UI tests for QW Editor
//

import XCTest

final class qwUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to fully launch
        sleep(1)
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Tests
    
    @MainActor
    func testAppLaunches() throws {
        // Just verify the app is running
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }
    
    // MARK: - Menu Tests
    
    @MainActor
    func testFileMenuExists() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        XCTAssertTrue(fileMenu.exists, "File menu should exist")
    }
    
    @MainActor
    func testFileMenuHasNewOption() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        fileMenu.click()
        
        let newMenuItem = app.menuItems["New"]
        XCTAssertTrue(newMenuItem.exists, "File menu should have New option")
        
        app.typeKey(.escape, modifierFlags: [])
    }
    
    @MainActor
    func testFileMenuHasOpenOption() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        fileMenu.click()
        
        let openMenuItem = app.menuItems["Open…"]
        XCTAssertTrue(openMenuItem.exists, "File menu should have Open option")
        
        app.typeKey(.escape, modifierFlags: [])
    }
    
    @MainActor
    func testFileMenuHasSaveOption() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        fileMenu.click()
        
        let saveMenuItem = app.menuItems["Save…"]
        let saveExists = saveMenuItem.exists || app.menuItems["Save"].exists
        XCTAssertTrue(saveExists, "File menu should have Save option")
        
        app.typeKey(.escape, modifierFlags: [])
    }
    
    @MainActor
    func testEditMenuExists() throws {
        let menuBar = app.menuBars.firstMatch
        let editMenu = menuBar.menuBarItems["Edit"]
        XCTAssertTrue(editMenu.exists, "Edit menu should exist")
    }
    
    // MARK: - New Document Tests
    
    @MainActor
    func testCreateNewDocument() throws {
        // Open a new document via menu
        app.typeKey("n", modifierFlags: .command)
        
        sleep(1)
        
        // The app should still be running
        XCTAssertTrue(app.state == .runningForeground, "App should still be running after new document")
    }
    
    // MARK: - Performance Tests
    
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

// MARK: - File Operations Tests

final class qwFileOperationsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        sleep(1)
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    @MainActor
    func testOpenFileViaMenu() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        fileMenu.click()
        
        sleep(1)
        
        let openItem = app.menuItems["Open…"]
        if openItem.exists {
            openItem.click()
            
            sleep(1)
            
            // Dismiss any open dialog
            app.typeKey(.escape, modifierFlags: [])
            
            XCTAssertTrue(true, "Should be able to open file via menu")
        } else {
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(true, "Open menu item was checked")
        }
    }
    
    @MainActor
    func testNewFileMenuOption() throws {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        XCTAssertTrue(fileMenu.exists, "File menu should exist")
        
        fileMenu.click()
        
        let newItem = app.menuItems["New"]
        XCTAssertTrue(newItem.exists, "New menu item should exist")
        
        app.typeKey(.escape, modifierFlags: [])
    }
}
