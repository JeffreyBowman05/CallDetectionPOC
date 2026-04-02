//
//  CallObserver.swift
//  CallESP32
//
//  Created by developer on 1/8/26.
//

import CallKit

final class CallObserver : NSObject, CXCallObserverDelegate {
    
    private let observer = CXCallObserver()
    var onChange: ((String) -> Void)?
    
    override init(){
        super.init()
        observer.setDelegate(self, queue: nil)
    }
    
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        
    
        
        if call.hasEnded {
            onChange?("ENDED")
        }
        
        else if call.hasConnected {
            onChange?("ACTIVE")
        }	
        
        else {
            onChange?("INCOMING CALL")
        }
    }
}
