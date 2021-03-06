//
//  ScansPurchaseTracker.swift
//  SmartReceipts
//
//  Created by Bogdan Evsenev on 24/10/2017.
//  Copyright © 2017 Will Baumann. All rights reserved.
//

import RxSwift

class ScansPurchaseTracker: NSObject {
    private let bag = DisposeBag()
    private let purchaseService = PurchaseService()
    static let shared = ScansPurchaseTracker()
    
    var remainingScans: Int { return LocalScansTracker.shared.scansCount }
    var hasAvailableScans: Bool { return remainingScans > 0 }
    
    private override init() {}
    
    func initialize() {
        purchaseService.cacheProducts()
        AuthService.shared.loggedInObservable
            .filter({ $0 })
            .flatMap({ _ -> Observable<Int> in
                return self.fetchAndPersistAvailableRecognitions()
            }).subscribe()
            .disposed(by: bag)
        
        purchaseService.sendReceipt()
    }
    
    func decrementRemainingScans() {
        LocalScansTracker.shared.scansCount -= 1
    }
    
    func fetchAndPersistAvailableRecognitions() -> Observable<Int> {
        return AuthService.shared.getUser()
            .filter({ $0 != nil })
            .flatMap({ user -> Observable<Int> in
                return Observable.just(user!.scansAvailable)
            }).do(onNext: { count in
                LocalScansTracker.shared.scansCount = count
            })
    }
}

extension Reactive where Base: ScansPurchaseTracker {
    var remainingScans: Observable<Int> { return LocalScansTracker.shared.rx.scansCount }
}
