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
    func viewContains(point: CGPoint) -> Bool
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
//    var pinchPolicy: EllipseView.EditingPolicy {
//        get {
//            ellipseView.editingPolicy
//        }
//        set {
//            ellipseView.editingPolicy = newValue
//            ellipseView.setNeedsDisplay()
//        }
//    }
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
        let pan = UIPanGestureRecognizer(target: view, action: #selector(EllipseView.handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        
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
            if !(view as! EllipseView).selected {
                gesture.state = .failed
                return
            }
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
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer {
            return (view as! EllipseView).selected
        }
        return true
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
            blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
            if !(view as! EllipseView).selected {
                gesture.state = .failed
                return
            }
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
            if !(view as! EllipseView).selected {
                gesture.state = .failed
                return
            }
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
    
    func viewContains(point: CGPoint) -> Bool {
        return self.insideEllipse(point)
    }
    
    func resetEllipsePinchPolicy() {
        (view as! EllipseView).editingPolicy = .unselected
        self.view.setNeedsDisplay()
    }
}

class EllipseView: UIView {
    enum EditingPolicy {
        case unselected
        case pinchHV
        case pinchHorizontal
        case pinchVertical
        mutating func toggle() {
            switch self {
            case .unselected:
                self = .pinchHV
            case .pinchHV:
                self = .pinchHorizontal
            case .pinchHorizontal:
                self = .pinchVertical
            case .pinchVertical:
                self = .unselected
            }
        }
    }
    var editingPolicy: EditingPolicy = .pinchHV
    var cornerRadius: CGFloat = 20
    var selected: Bool {
        self.editingPolicy != .unselected
    }
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
        
        if selected {
            let width = 2.0
            context.setStrokeColor(UIColor.yellow.cgColor)
            context.setLineWidth(width)
            // dash line ellpise
            context.setLineDash(phase: 0, lengths: [10, 10])
            context.addPath(UIBezierPath(ovalIn: rect.insetBy(dx: width / 2, dy: width / 2)).cgPath)
            context.strokePath()
        }
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
        switch gesture.state {
        case .began:
            gesture.setTranslation(.zero, in: self)
            self.delegate?.handlePan(gesture)
        case _:
            self.delegate?.handlePan(gesture)
        }
    }
//    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
//        let view = super.hitTest(point, with: event)
//        guard view === self else { return view }
//        switch self.delegate?.viewContains(point: point) {
//        case .some(true) where self.selected:
//            return self
//        case _:
//            return nil
//        }
//    }
}
