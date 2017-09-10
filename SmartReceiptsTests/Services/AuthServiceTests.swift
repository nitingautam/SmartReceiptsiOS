//
//  AuthServiceTests.swift
//  SmartReceipts
//
//  Created by Bogdan Evsenev on 08/09/2017.
//  Copyright © 2017 Will Baumann. All rights reserved.
//

@testable import SmartReceipts
import XCTest
import RxSwift
import RxTest
import RxBlocking

class AuthServiceTests: XCTestCase {
    
    let authService = AuthService()
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testLogin() {
        let scheduler = TestScheduler(initialClock: 0)
        let loggedInObserver = scheduler.createObserver(Bool.self)
        
        let loggedCheck = [
            next(0, false),
            next(0, true)
        ]
        
        scheduler.start()
        
        _ = AuthService.isLoggedIn.bind(to: loggedInObserver)
        
        let token = try! authService.login(credentials: Credentials("aaaa@aaaa.aaa", "12345678"))
            .toBlocking(timeout: 3)
            .first()!
        
        let savedToken = try! authService.token.toBlocking().first()!
        
        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(token, savedToken)
        XCTAssertEqual(loggedCheck, loggedInObserver.events)
    }
    
    func testSignUp() {
        let scheduler = TestScheduler(initialClock: 0)
        let loggedInObserver = scheduler.createObserver(Bool.self)
        
        let loggedCheck = [
            next(0, false),
            next(0, true)
        ]
        
        scheduler.start()
        
        _ = AuthService.isLoggedIn.bind(to: loggedInObserver)
        
        let token = try! authService.signup(credentials: Credentials("aaaa@aaaa.aaa", "12345678"))
            .toBlocking(timeout: 3)
            .first()!
        
        let savedToken = try! authService.token.toBlocking().first()!
        
        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(token, savedToken)
        XCTAssertEqual(loggedCheck, loggedInObserver.events)
    }
    
    func testLogout() {
        _ = try? authService.login(credentials: Credentials("aaaa@aaaa.aaa", "12345678"))
            .toBlocking(timeout: 3)
            .first()
        let call = try? authService.logout().toBlocking(timeout: 3).first()
        XCTAssertTrue(call != nil)
    }
}
