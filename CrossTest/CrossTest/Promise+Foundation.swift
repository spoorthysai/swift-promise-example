//
//  Promise.swift
//  CrossTest
//
//  Created by Loreto Parisi on 16/12/15.
//  Copyright © 2015 Musixmatch. All rights reserved.
//

import Foundation


class Deferred: Promise {
    
    var promise:Promise
    
    override convenience init() {
        self.init(promise: Promise())
    }
    
    private init(promise: Promise) {
        self.promise = promise
    }
    
    func resolve(value: AnyObject?) {
        promise.doResolve(value)
    }
    
    func reject(error: AnyObject?) {
        promise.doReject(error)
    }
    
    override func then(then: thenClosure) -> Promise {
        return promise.then(then)
    }
    
    override func catch_(catch_: catchClosure) -> Promise {
        return promise.catch_(catch_)
    }
    
    override func finally(finally: finallyClosure) -> Promise {
        return promise.finally(finally)
    }
    
}

class Promise {
    
    enum Status: String {
        case PENDING = "Pending"
        case RESOLVED = "Resolved"
        case REJECTED = "Rejected"
    }
    
    typealias thenClosure = (AnyObject?) -> (AnyObject?)
    typealias thenClosureNoReturn = (AnyObject?) -> ()
    typealias catchClosure = (AnyObject?) -> ()
    typealias finallyClosure = () -> ()
    typealias promiseClosure = ( (AnyObject?) -> (), (AnyObject?) -> () ) -> ()
    
    
    var thens = Array<thenClosure>()
    var cat: catchClosure?
    var fin: finallyClosure?
    
    var value: AnyObject?
    
    var _status: Status = .PENDING
    private var statusObserver: ( (Promise) -> () )?
    var status: Status {
        get {
            return _status
        }
        set(status) {
            _status = status
            statusObserver?(self)
        }
    }
    
    private init() {
        
    }
    
    func then(then: thenClosureNoReturn) -> Promise {
        self.then { (value) -> (AnyObject?) in
            then(value)
            return nil
        }
        
        return self
    }
    
    func then(then: thenClosure) -> Promise {
        self.sync { () in
            
            if (self.status == .PENDING) {
                self.thens.append(then)
            } else if (self.status == .RESOLVED) {
                then(self.value)
            }
            
        }
        
        return self
    }
    
    func catch_(catch_: catchClosure) -> Promise {
        if (self.cat != nil) { return self }
        
        self.sync { () in
            
            if (self.status == .PENDING) {
                self.cat = catch_
            } else if (self.status == .REJECTED) {
                catch_(self.value)
            }
            
        }
        
        return self
    }
    
    func finally(finally: finallyClosure) -> Promise {
        if (self.fin != nil) { return self }
        
        self.sync { () in
            
            if (self.status == .PENDING) {
                self.fin = finally
            } else {
                finally()
            }
            
        }
        
        return self
    }
    
    /*func sync(closure: () -> ()) {
        let lockQueue = dispatch_queue_create("com.rokkincat.promises.LockQueue", nil)
        dispatch_sync(lockQueue, closure)
    }*/
    
    func sync<T>(lock: AnyObject, @noescape closure: () -> T) -> T {
        objc_sync_enter(lock)
        defer {
            objc_sync_exit(lock)
        }
        return closure()
    }
    
    private func doResolve(value: AnyObject?, shouldRunFinally: Bool = true) {
        self.sync { () in
            if (self.status != .PENDING) { return }
            self.value = value
            
            var chain: Promise?
            
            var paramValue: AnyObject? = self.value
            for (_, then) in self.thens.enumerate() {
                
                // If a chain is hit, add the then
                if (chain != nil) { chain?.then(then); return }
                
                let ret: AnyObject? = then(paramValue)
                if let retPromise = ret as? Promise {
                    
                    // Set chained promised
                    chain = retPromise
                    
                    // // Transfer catch and finally to chained promise
                    if (self.cat != nil) { chain?.catch_(self.cat!); self.cat = nil }
                    if (self.fin != nil) { chain?.finally(self.fin!); self.fin = nil }
                    
                } else if let retAny: AnyObject = ret {
                    paramValue = retAny
                }
                
            }
            
            // Run the finally
            if (shouldRunFinally) {
                if (chain == nil) {
                    self.doFinally(.RESOLVED)
                }
            }
        }
    }
    
    private func doReject(error: AnyObject?, shouldRunFinally: Bool = true) {
        self.sync { () in
            if (self.status != .PENDING) { return }
            self.value = error
            
            self.cat?(self.value)
            if (shouldRunFinally) { self.doFinally(.REJECTED) }
        }
    }
    
    private func doFinally(status: Status) {
        if (self.status != .PENDING) { return }
        self.status = status
        self.fin?()
    }
    
}

extension Promise  {
    
    convenience init(promiseClosure: ( resolve: (AnyObject?) -> (), reject: (AnyObject?) -> () ) -> ()) {
        self.init()
        
        let deferred = Deferred(promise: self)
        promiseClosure( resolve: deferred.resolve, reject: deferred.reject )
    }
    
}

extension Promise {
    
    class func all(promises: Array<Promise>) -> Promise {
        return All(promises: promises)
    }
    
    private class All: Promise {
        
        var promises = Array<Promise>()
        
        var promiseCount: Int = 0
        var numberOfResolveds: Int = 0
        var numberOfRejecteds: Int = 0
        var total: Int {
            get { return numberOfResolveds + numberOfRejecteds }
        }
        private var statusToChangeTo: Status = .PENDING
        
        private func observe(promise: Promise) {
            self.sync { () in
                switch promise.status {
                case .RESOLVED:
                    self.numberOfResolveds++
                case .REJECTED:
                    self.numberOfRejecteds++
                    if (self.statusToChangeTo == .PENDING) {
                        self.statusToChangeTo = .REJECTED
                        self.doReject(promise.value, shouldRunFinally: false)
                    }
                default:
                    0 // noop
                }
                
                if (self.total >= self.promiseCount) {
                    if (self.statusToChangeTo == .PENDING) {
                        self.statusToChangeTo = .RESOLVED
                        
                        // Need to filter out nil values before mapping values to array
                        let filteredNils = self.promises.filter( { (p) -> (Bool) in return (p.value != nil) } )
                        let values = filteredNils.map( { (p) -> (AnyObject) in print(p.value); return p.value! } )
                        
                        self.doResolve(values, shouldRunFinally: false)
                    }
                    
                    self.doFinally(self.statusToChangeTo)
                }
                
            }
        }
        
        init(promises: Array<Promise>) {
            super.init()
            self.promiseCount = promises.count
            
            for promise in promises {
                let p = (promise as? Deferred == nil) ?
                    promise :
                    (promise as! Deferred).promise
                self.promises.append(p)
                p.statusObserver = observe
            }
            
        }
        
    }
    
}
