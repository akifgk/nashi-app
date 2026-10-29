import Foundation

/// A browser can publish its drag before the first sampled pressed-button state.
/// Give that edge 200 ms without treating a completed drag as new on the next click.
struct DragPasteboardSession {
    private var baseline:Int?
    private var previous:Int?
    private var changedAt:TimeInterval = -.infinity
    private var wasDown=false
    mutating func containsFreshDrag(isDown:Bool,changeCount:Int,now:TimeInterval)->Bool {
        if baseline==nil { baseline=changeCount }
        if let previous,previous != changeCount { changedAt=now }
        defer { previous=changeCount;wasDown=isDown }
        if !isDown {
            if wasDown || now-changedAt>0.2 { baseline=changeCount }
            return false
        }
        return changeCount != baseline
    }
}
