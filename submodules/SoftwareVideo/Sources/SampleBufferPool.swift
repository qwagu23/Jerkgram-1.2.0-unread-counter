import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit

private final class SampleBufferLayerImplNullAction: NSObject, CAAction {
    @objc func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

private final class SampleBufferLayerImpl: AVSampleBufferDisplayLayer {
    override func action(forKey event: String) -> CAAction? {
        return SampleBufferLayerImplNullAction()
    }
}

public final class SampleBufferLayer {
    public let layer: AVSampleBufferDisplayLayer
    private let enqueue: () -> Void
    
    public var isFreed: Bool = false
    fileprivate init(layer: AVSampleBufferDisplayLayer, enqueue: @escaping () -> Void) {
        self.layer = layer
        self.enqueue = enqueue
    }
    
    deinit {
        if !self.isFreed {
            self.enqueue()
        }
    }
}

private final class SampleBufferLayerContext {
    let layer: AVSampleBufferDisplayLayer
    let synchronizer: AVSampleBufferRenderSynchronizer
    let receiver: AVSampleBufferVideoRenderer.Receiver

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
        self.synchronizer = AVSampleBufferRenderSynchronizer()
        self.receiver = self.synchronizer.sampleBufferReceiver(adding: layer.sampleBufferRenderer)
    }
}

private let pool = Atomic<[SampleBufferLayerContext]>(value: [])

public func clearSampleBufferLayerPoll() {
    let _ = pool.modify { _ in return [] }
}

public func takeSampleBufferLayer() -> SampleBufferLayer {
    var context: SampleBufferLayerContext?
    let _ = pool.modify { list in
        var list = list
        if !list.isEmpty {
            context = list.removeLast()
        }
        return list
    }
    if context == nil {
        context = SampleBufferLayerContext(layer: SampleBufferLayerImpl())
    }
    let layerContext = context!
    return SampleBufferLayer(layer: layerContext.layer, enqueue: {
        Queue.mainQueue().async {
            Task {
                await layerContext.receiver.flush(removingDisplayedImage: true)
                Queue.mainQueue().async {
                    layerContext.layer.setAffineTransform(CGAffineTransform.identity)
                    #if targetEnvironment(simulator)
                    #else
                    let _ = pool.modify { list in
                        var list = list
                        list.append(layerContext)
                        return list
                    }
                    #endif
                }
            }
        }
    })
}
