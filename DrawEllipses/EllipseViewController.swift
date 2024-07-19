//
//  EllipseViewController.swift
//  DrawEllipses
//
//  Created by jsr on 2024/7/19.
//

import Foundation
import SwiftUI
import UIKit

protocol EllipseViewControllerDelegate: AnyObject {
    func informEllipseWasRemoved(_ controller: EllipseViewController)
    func informEllipseWasUpdated(_ controller: EllipseViewController)
}

protocol EllipseViewDelegate: AnyObject {
    func handlePan(_ gesture: UIPanGestureRecognizer)
}

class CGPointBox: NSObject {
    var unbox: CGPoint
    init(_ value: CGPoint) {
        self.unbox = value
    }
    override var description: String {
        return "CGPointBox\(unbox)@\(Unmanaged.passUnretained(self).toOpaque())"
    }
}

class EllipseViewController: UIViewController, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate, EllipseViewDelegate {
    
    var ellipseView: EllipseView!
    var state: EllipseState
//    enum PanAngle {
//        /// fixed(angle, startLocation, axisVector)
//        ///  - angle: the angle of pan direction (can only be `0`°, `90`°, `180`°, `-90`°)
//        ///  - startLocation: the location from which the scale factor is calculated (e.g. when pan rightwards, the horizontal scale factor is calculated from the ratio `(currentLocation.x - startLocation.x) / (endLocation.x - startLocation.x))`
//        ///  - axisVector: the normalized vector of the axis along which the pan direction is fixed
//        case fixed(Angle, start: CGPoint, axis: CGPoint)
//        /// free(withRespectTo)
//        ///  - withRespectTo: the scale factor is calculated from the component-wise ratio `(currentLocation - withRespectTo) / (startLocation - withRespectTo)`, where `currentLocation` is the current location of the pan gesture, `startLocation` is the location when the pan gesture began
//        case free(withRespectTo: CGPoint, start: CGPoint)
//    }
//    var panAngle: PanAngle? = nil // only for pan stretching
    weak var delegate: EllipseViewControllerDelegate? // usually the parent view controller
    weak var blockUndoRedoButtonDelegate: BlockUndoRedoButtonDelegate?
    init(center: CGPoint, a: CGFloat, b: CGFloat, color: UIColor, angle: Angle = .zero) {
        assert(a > 0 && b > 0)
        self.state = EllipseState(center: center, a: a, b: b, color: color, angle: angle)
        logger.info("init with center=\(center), a=\(a), b=\(b), color=\(color), angle=\(angle.degrees)°")
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 创建一个椭圆视图
        let rectOrigin = CGPoint(x: state.center.x - state.a, y: state.center.y - state.b)
        ellipseView = EllipseView(frame: CGRect(origin: rectOrigin, size: state.size))
        ellipseView.backgroundColor = .clear
        ellipseView.transform = CGAffineTransform(rotationAngle: state.angle.radians)
        ellipseView.delegate = self
        ellipseView.blockUndoRedoButtonDelegate = blockUndoRedoButtonDelegate!
        self.view = ellipseView
        
        // 添加手势识别器
        addGestureRecognizers(to: ellipseView)
    }
    
    func insideEllipse(_ p: CGPoint) -> Bool {
        var x = p.x - view.center.x
        var y = p.y - view.center.y
        // rotate back
        let angle = -state.angle - state.deltaAngle
        let (cos, sin) = (cos(angle.radians), sin(angle.radians))
        (x, y) = (x * cos - y * sin, x * sin + y * cos)
        logger.log("insideEllipse: \(p) -> (\(x), \(y))")
        return x * x / (state.a * state.a) + y * y / (state.b * state.b) <= 1
    }
    
    func addGestureRecognizers(to view: UIView) {
        // 手势
        view.addGestureRecognizer(
            UIPanGestureRecognizer(target: view, action: #selector(EllipseView.handlePan(_:))))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        view.addGestureRecognizer(rotation)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        // 长按手势
        let interaction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        view.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))))
    }
    
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var actions = suggestedActions
        actions.append(
            UIAction(title: "", image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
                self.deleteEllipse(nil)
        })
        return UIMenu(children: actions)
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        (view as! EllipseView).editingPolicy.toggle()
        view.setNeedsDisplay()
    }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .began:
            assert(state.translation == .zero)
            gesture.setTranslation(.zero, in: view.superview)
            blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
        case .changed:
            state.translation += gesture.translation(in: view.superview)
            view.center = state.center + state.translation
            gesture.setTranslation(.zero, in: view.superview)
        case .ended:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
            assert(state.center + state.translation == view.center)
            self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoPan(oldCenter:)), object: CGPointBox(state.center))
            logger.debug("panned: from \(self.state.center) to \(self.state.center + self.state.translation)")
            state = state.applyTranslation()
        default:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
        }
    }
    
    @objc func undoPan(oldCenter: CGPointBox) {
        assert(state.translation == .zero)
        self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoPan(oldCenter:)), object: CGPointBox(state.center))
        state.center = oldCenter.unbox
        view.center = oldCenter.unbox
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIRotationGestureRecognizer && (view as! EllipseView).editingPolicy == .pinchHV
    }
    
//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//        return gestureRecognizer is UIPinchGestureRecognizer &&
//            (view as! EllipseView).editingPolicy != .pinchHV &&
//            (otherGestureRecognizer is UITapGestureRecognizer ||
//             otherGestureRecognizer is UIRotationGestureRecognizer)
//    }
    
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            assert(state.deltaA == .zero && state.deltaB == .zero)
            gesture.scale = 1
//            logger.log("pinch: \(gesture.numberOfTouches) touches")
            blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
//            (0..<gesture.numberOfTouches).map { gesture.location(ofTouch: $0, in: view) }.first { !insideEllipse($0) }.map {
//                gesture.state = .failed
//                logger.debug("pinch: at \($0) outside the ellipse")
//                return
//            }
        case .changed:
            if (view as! EllipseView).editingPolicy != .pinchVertical {
                state.deltaA += (gesture.scale - 1) * state.a
            }
            if (view as! EllipseView).editingPolicy != .pinchHorizontal {
                state.deltaB += (gesture.scale - 1) * state.b
            }
            view.bounds.size = state.size
            view.setNeedsDisplay()
            gesture.scale = 1
        case .ended:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
            self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoPinch(oldScale:)), object: CGPointBox(.init(x: state.a, y: state.b)))
            logger.debug("pinched: from a=\(self.state.a), b=\(self.state.b) to a=\(self.state.a + self.state.deltaA), b=\(self.state.b + self.state.deltaB)")
            state.a += state.deltaA
            state.b += state.deltaB
            state.deltaA = 0
            state.deltaB = 0
        default:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
        }
    }
    
    @objc func undoPinch(oldScale: CGPointBox) {
        assert(state.deltaA == .zero && state.deltaB == .zero)
        logger.log("undoPinch: from a=\(self.state.a), b=\(self.state.b) to a=\(oldScale.unbox.x), b=\(oldScale.unbox.y)")
        self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoPinch(oldScale:)), object: CGPointBox(.init(x: state.a, y: state.b)))
        state.a = oldScale.unbox.x
        state.b = oldScale.unbox.y
        view.bounds.size = state.size
        view.setNeedsDisplay()
    }
    
    @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            assert(state.deltaAngle == .zero)
            gesture.rotation = 0
            logger.log("rotate: \(gesture.numberOfTouches) touches")
            blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
        case .changed:
            state.deltaAngle += .radians(gesture.rotation)
            view.transform = CGAffineTransform(rotationAngle: state.currentAngle.radians)
            gesture.rotation = 0
        case .ended:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
            self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoRotation(oldAngle:)), object: NSNumber(value: state.angle.radians))
            logger.debug("rotated: from \(self.state.angle.degrees)° to \(self.state.currentAngle.degrees)°")
            state = state.applyRotation()
        default:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
        }
    }
    
    @objc func undoRotation(oldAngle: NSNumber) {
        assert(state.deltaAngle == .zero)
        logger.log("undoRotation: from \(self.state.angle.degrees)° to \(oldAngle)")
        self.undoManager?.registerUndo(withTarget: self, selector: #selector(undoRotation(oldAngle:)), object: NSNumber(value: state.angle.radians))
        state.angle = Angle(radians: oldAngle.doubleValue)
        view.transform = CGAffineTransform(rotationAngle: state.angle.radians)
    }
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let location = gesture.location(in: view)
            if let interaction = self.view.interactions.first(where: { $0 is UIEditMenuInteraction }) as? UIEditMenuInteraction {
                let configuration = UIEditMenuConfiguration(identifier: "ellipseLongPressConfig", sourcePoint: location)
                interaction.presentEditMenu(with: configuration)
            }
        default:
            break
        }
    }
    
    @objc func deleteEllipse(_ sender: Any?) {
        delegate?.informEllipseWasRemoved(self)
    }
    
    @objc func undo() {
        undoManager?.undo()
    }
    
    @objc func redo() {
        undoManager?.redo()
    }
    func resetEllipsePinchPolicy() {
        (self.view as! EllipseView).editingPolicy = .pinchHV
        self.view.setNeedsDisplay()
    }
}

class EllipseView: UIView {
    enum EditingPolicy {
        case pinchHV
        case pinchHorizontal
        case pinchVertical
        mutating func toggle() {
            switch self {
            case .pinchHV:
                self = .pinchHorizontal
            case .pinchHorizontal:
                self = .pinchVertical
            case .pinchVertical:
                self = .pinchHV
            }
        }
    }
    var editingPolicy: EditingPolicy = .pinchHV
    var cornerRadius: CGFloat = 20
    weak var blockUndoRedoButtonDelegate: BlockUndoRedoButtonDelegate?
    weak var delegate: EllipseViewDelegate?
    var corners: [CGPoint] {
        [
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ]
    }
    
    var antipodeCorner: [CGPoint] {
        return [
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            bounds.origin,
            CGPoint(x: bounds.maxX, y: bounds.minY)
        ]
    }
    enum StretchDirection {
        case horizontal(from: CGPoint)
        case vertical(from: CGPoint)
        case free(from: CGPoint, antipodeCorner: CGPoint)
    }
    var stretchDirection: StretchDirection? = nil
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.black.cgColor)
        context.fillEllipse(in: rect)
        // bounding box
        switch editingPolicy {
        case .pinchHorizontal:
            // show |<-  ->|
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(2)
            let right = CGPoint(x: rect.maxX, y: rect.midY)
            context.move(to: right)
            context.addLine(to: right - .init(x: 20, y: 0))
            context.move(to: right)
            context.addLine(to: right - .init(x: 10, y: 10))
            context.move(to: right)
            context.addLine(to: right - .init(x: 10, y: -10))
            context.move(to: right - .init(x: 0, y: 10))
            context.addLine(to: right - .init(x: 0, y: -10))
            let left = CGPoint(x: rect.minX, y: rect.midY)
            context.move(to: left)
            context.addLine(to: left + .init(x: 20, y: 0))
            context.move(to: left)
            context.addLine(to: left + .init(x: 10, y: 10))
            context.move(to: left)
            context.addLine(to: left + .init(x: 10, y: -10))
            context.move(to: left + .init(x: 0, y: 10))
            context.addLine(to: left + .init(x: 0, y: -10))
            context.strokePath()
        case .pinchVertical:
            // show |^  v|
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(2)
            let top = CGPoint(x: rect.midX, y: rect.minY)
            context.move(to: top)
            context.addLine(to: top + .init(x: 0, y: 20))
            context.move(to: top)
            context.addLine(to: top + .init(x: 10, y: 10))
            context.move(to: top)
            context.addLine(to: top + .init(x: -10, y: 10))
            context.move(to: top + .init(x: 10, y: 0))
            context.addLine(to: top + .init(x: -10, y: 0))
            let bottom = CGPoint(x: rect.midX, y: rect.maxY)
            context.move(to: bottom)
            context.addLine(to: bottom - .init(x: 0, y: 20))
            context.move(to: bottom)
            context.addLine(to: bottom - .init(x: 10, y: 10))
            context.move(to: bottom)
            context.addLine(to: bottom - .init(x: -10, y: 10))
            context.move(to: bottom - .init(x: 10, y: 0))
            context.addLine(to: bottom - .init(x: -10, y: 0))
            context.strokePath()
        default:
            break
        }
        // horizontal arrow
//        context.setStrokeColor(UIColor.blue.cgColor)
//        context.setLineWidth(1)
//        context.move(to: CGPoint(x: rect.midX - 20, y: rect.midY))
//        context.addLine(to: CGPoint(x: rect.midX + 20, y: rect.midY))
//        context.move(to: CGPoint(x: rect.midX + 20, y: rect.midY))
//        context.addLine(to: CGPoint(x: rect.midX + 10, y: rect.midY - 5))
//        context.move(to: CGPoint(x: rect.midX + 20, y: rect.midY))
//        context.addLine(to: CGPoint(x: rect.midX + 10, y: rect.midY + 5))
//        context.strokePath()
//        // vertical arrow
//        context.setStrokeColor(UIColor.red.cgColor)
//        context.move(to: CGPoint(x: rect.midX, y: rect.midY - 20))
//        context.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 20))
//        context.move(to: CGPoint(x: rect.midX, y: rect.midY + 20))
//        context.addLine(to: CGPoint(x: rect.midX - 5, y: rect.midY + 10))
//        context.move(to: CGPoint(x: rect.midX, y: rect.midY + 20))
//        context.addLine(to: CGPoint(x: rect.midX + 5, y: rect.midY + 10))
//        context.strokePath()
     }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        assert(gesture.view === self)
        switch (gesture.state, stretchDirection) {
        case (.began, _):
            gesture.setTranslation(.zero, in: self)
//            if editingPolicy {
//                let location = gesture.location(in: self)
//                let velocity = gesture.velocity(in: self)
//                for (i, corner) in corners.enumerated() {
//                    if distance(from: location, to: corner) < cornerRadius {
//                        blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
//                        logger.debug("panned: on corner \(i) at \(corner), velocity=\(velocity)")
//                        let angle = atan2(velocity.y, velocity.x)
//                        switch angle / CGFloat.pi * 180 {
//                        case -10..<10, -180..<(-170), 170..<180:
//                            stretchDirection = .horizontal(from: location)
//                        case 80..<100, -100..<(-80):
//                            stretchDirection = .vertical(from: location)
//                        default:
//                            stretchDirection = .free(from: location, antipodeCorner: antipodeCorner[i])
//                        }
//                        return
//                    }
//                }
//            } else {
                stretchDirection = nil
                self.delegate?.handlePan(gesture)
//            }
        case (_, .none):
            self.delegate?.handlePan(gesture)
        case (.changed, .some(let direction)):
            let location = gesture.location(in: self)
            let translation = gesture.translation(in: self)
            switch direction {
            case .horizontal(let from):
                let dx = location.x - from.x;
                bounds = bounds.insetBy(dx: -dx / 2, dy: 0)
//                bounds.origin.x += dx / 2
            case .vertical(let from):
                let dy = location.y - from.y;
                bounds = bounds.insetBy(dx: 0, dy: -dy / 2)
//                bounds.origin.y += dy / 2
            case .free(let from, let antipodeCorner):
                let dx = location.x - from.x
                let dy = location.y - from.y
                bounds = bounds.insetBy(dx: -dx / 2, dy: -dy / 2)
//                bounds.origin.x += dx / 2
//                bounds.origin.y += dy / 2
            }
            gesture.setTranslation(.zero, in: self)
        case (.ended, .some(_)):
            stretchDirection = nil
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
        default:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
            break
        }
    }
}
