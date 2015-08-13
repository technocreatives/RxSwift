//
//  Catch.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/19/15.
//  Copyright (c) 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

// catch with callback

class CatchSinkProxy<O: ObserverType> : ObserverType {
    typealias Element = O.Element
    typealias Parent = CatchSink<O>
    
    let parent: Parent
    
    init(parent: Parent) {
        self.parent = parent
    }
    
    func on(event: Event<Element>) {
        parent.observer?.on(event)
        
        switch event {
        case .Next:
            break
        case .Error:
            parent.dispose()
        case .Completed:
            parent.dispose()
        }
    }
}

class CatchSink<O: ObserverType> : Sink<O>, ObserverType {
    typealias Element = O.Element
    typealias Parent = Catch<Element>
    
    let parent: Parent
    let subscription = SerialDisposable()
    
    init(parent: Parent, observer: O, cancel: Disposable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        let disposableSubscription = parent.source.subscribeSafe(self)
        subscription.disposable = disposableSubscription
        
        return subscription
    }
    
    func on(event: Event<Element>) {
        switch event {
        case .Next:
            observer?.on(event)
        case .Completed:
            observer?.on(event)
            self.dispose()
        case .Error(let error):
            do {
                let catchSequence = try parent.handler(error)

                let observer = CatchSinkProxy(parent: self)
                
                let subscription2 = catchSequence.subscribeSafe(observer)
                subscription.disposable = subscription2
            }
            catch let e {
                observer?.on(.Error(e))
                self.dispose()
            }
        }
    }
}

class Catch<Element> : Producer<Element> {
    typealias Handler = (ErrorType) throws -> Observable<Element>
    
    let source: Observable<Element>
    let handler: Handler
    
    init(source: Observable<Element>, handler: Handler) {
        self.source = source
        self.handler = handler
    }
    
    override func run<O: ObserverType where O.Element == Element>(observer: O, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = CatchSink(parent: self, observer: observer, cancel: cancel)
        setSink(sink)
        return sink.run()
    }
}

// catch to result

// O: ObserverType caused compiler crashes, so let's leave that for now
class CatchToResultSink<ElementType> : Sink<Observer<RxResult<ElementType>>>, ObserverType {
    typealias Element = ElementType
    typealias Parent = CatchToResult<Element>
    
    let parent: Parent
    
    init(parent: Parent, observer: Observer<RxResult<Element>>, cancel: Disposable) {
        self.parent = parent
        super.init(observer: observer, cancel: cancel)
    }
    
    func run() -> Disposable {
        return parent.source.subscribeSafe(self)
    }
    
    func on(event: Event<Element>) {
        switch event {
        case .Next(let value):
            observer?.on(.Next(success(value)))
        case .Completed:
            observer?.on(.Completed)
            self.dispose()
        case .Error(let error):
            observer?.on(.Next(failure(error)))
            observer?.on(.Completed)
            self.dispose()
        }
    }
}

class CatchToResult<Element> : Producer <RxResult<Element>> {
    let source: Observable<Element>
    
    init(source: Observable<Element>) {
        self.source = source
    }
    
    override func run<O: ObserverType where O.Element == RxResult<Element>>(observer: O, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = CatchToResultSink(parent: self, observer: Observer<RxResult<Element>>.normalize(observer), cancel: cancel)
        setSink(sink)
        return sink.run()
    }
}

// catch enumerable

class CatchSequenceSink<O: ObserverType> : TailRecursiveSink<O> {
    typealias Element = O.Element
    typealias Parent = CatchSequence<Element>
    
    var lastError: ErrorType?
    
    override init(observer: O, cancel: Disposable) {
        super.init(observer: observer, cancel: cancel)
    }
    
    override func on(event: Event<Element>) {
        switch event {
        case .Next:
            observer?.on(event)
        case .Error(let error):
            self.lastError = error
            self.scheduleMoveNext()
        case .Completed:
            self.observer?.on(event)
            self.dispose()
        }
    }
    
    override func done() {
        if let lastError = self.lastError {
            observer?.on(.Error(lastError))
        }
        else {
            observer?.on(.Completed)
        }
        
        self.dispose()
    }
    
    override func extract(observable: Observable<Element>) -> AnyGenerator<Observable<O.Element>>? {
        if let onError = observable as? CatchSequence<Element> {
            return onError.sources.generate()
        }
        else {
            return nil
        }
    }
}

class CatchSequence<Element> : Producer<Element> {
    let sources: AnySequence<Observable<Element>>
    
    init(sources: AnySequence<Observable<Element>>) {
        self.sources = sources
    }
    
    override func run<O : ObserverType where O.Element == Element>(observer: O, cancel: Disposable, setSink: (Disposable) -> Void) -> Disposable {
        let sink = CatchSequenceSink(observer: observer, cancel: cancel)
        setSink(sink)
        return sink.run(AnySequence(self.sources.generate()))
    }
}