//
//  DrawSceneViewController.swift
//  DrawEllipses
//
//  Created by jsr on 2024/7/19.
//

import Foundation
import UIKit
import Accelerate
import LASwift

extension CGPoint {
    static func +=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }
    static func -=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    static func *(lhs: CGFloat, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs * rhs.x, y: lhs * rhs.y)
    }
    static func *(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    static prefix func -(lhs: CGPoint) -> CGPoint {
        return CGPoint(x: -lhs.x, y: -lhs.y)
    }
    
    static func dot(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        return lhs.x * rhs.x + lhs.y * rhs.y
    }
}

extension CGPoint: CustomStringConvertible {
    public var description: String {
        return "(\(x), \(y))"
    }
}

extension CGSize: CustomStringConvertible {
    public var description: String {
        return "(\(width), \(height))"
    }
}

protocol BlockUndoRedoButtonDelegate: AnyObject {
    func disableUndoRedoButton(who: AnyObject)
    func enableUndoRedoButton(who: AnyObject)
}

class DrawSceneViewController: UIViewController, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate, SceneViewDelegate, EllipseViewControllerDelegate {
    
    private var points: [CGPoint] = []
    private var tot: Int = .zero
    weak var blockUndoRedoButtonDelegate: BlockUndoRedoButtonDelegate? {
        didSet {
            (self.view as! DrawSceneView).blockUndoRedoButtonDelegate = blockUndoRedoButtonDelegate
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        self.view.addInteraction(UIEditMenuInteraction(delegate: self))
        self.view.backgroundColor = .white
        (self.view as! DrawSceneView).delegate = self
    }
    
    func undo(){
        if let undoManager = self.undoManager, !undoManager.canUndo {
            logger.warning("nothing to undo")
        }
        undoManager?.undo()
    }
    
    func redo(){
        if let undoManager = self.undoManager, !undoManager.canRedo {
            logger.warning("nothing to redo")
        }
        undoManager?.redo()
    }

    @IBAction func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
                case .began:
                    let location = sender.location(in: self.view)
                    if let interaction = self.view.interactions.first(where: { $0 is UIEditMenuInteraction }) as? UIEditMenuInteraction {
                        let config = UIEditMenuConfiguration(identifier: "sceneLongPressConfig", sourcePoint: location)
                        interaction.presentEditMenu(with: config)
                    }
                default:
                    break
                }
                logger.log("handleLongPress! tot=\(self.tot)")
                self.tot += 1
    }
    
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var actions = suggestedActions
        actions.append(
            UIAction(title:"new ellipse", image: UIImage(systemName: "oval")) { action in
                let a = 100.0, b = 50.0
                let ellipse = EllipseViewController(center: configuration.sourcePoint, a: a, b: b, color: .black, angle: .zero)
                self.addEllipse(vc: ellipse)
        })
        return UIMenu(children: actions)
    }
    
    func fitEllipse(with points: [CGPoint]) {
        guard points.count > 4 else { return }
        // 构建设计矩阵 D
        let D = Matrix(points.count, 6, 0.0)
        for (i, point) in points.enumerated() {
            let x = point.x
            let y = point.y
            D[i, 0] = x * x
            D[i, 1] = x * y
            D[i, 2] = y * y
            D[i, 3] = x
            D[i, 4] = y
            D[i, 5] = 1.0
        }
        
        // 构建 S 矩阵
        let S = transpose(D) * D
        // 定义约束矩阵
        let C = Matrix([
            [0, 0, 2, 0, 0, 0],
            [0, -1, 0, 0, 0, 0],
            [2, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0]
        ])
        
        let (eigenVectors, eigenValueDiagonalMatrix) = eig(inv(S) * C)
        let minPositiveEigenvector = {
            // 找到最小的正特征值
            var minPositiveEigenvalue = Double.greatestFiniteMagnitude
            var minPositiveEigenvector: Vector = zeros(6)
            for i in 0..<6 {
                if eigenValueDiagonalMatrix[i, i] > 0 && eigenValueDiagonalMatrix[i, i] < minPositiveEigenvalue {
                    minPositiveEigenvalue = eigenValueDiagonalMatrix[i, i]
                    minPositiveEigenvector = eigenVectors[col: i]
                }
            }
            return minPositiveEigenvector
        }()
        
        if true {
            let F = minPositiveEigenvector[5]
            let A = minPositiveEigenvector[0] / F
            let B = minPositiveEigenvector[1] / F
            let C = minPositiveEigenvector[2] / F
            let D = minPositiveEigenvector[3] / F
            let E = minPositiveEigenvector[4] / F

            let origin = CGPoint(x: (B * E - 2 * C * D) / (4 * A * C - B * B),
                                 y: (B * D - 2 * A * E) / (4 * A * C - B * B))
            let angle = atan2(B, A - C) / 2
            let xx = origin.x * origin.x
            let xy = origin.x * origin.y
            let yy = origin.y * origin.y
            let nominator = 2 * (A * xx + C * yy + B * xy - 1.0)
            let a = sqrt(nominator / (A + C + sqrt((A - C) * (A - C) + B * B)))
            let b = sqrt(nominator / (A + C - sqrt((A - C) * (A - C) + B * B)))
            let ellipse = EllipseViewController(center: origin, a: a, b: b, color: .black, angle: .radians(angle))
            self.addEllipse(vc: ellipse)
            logger.info("fitting result: x(t) - \(origin.x) = \(a)cos(2πt + \(ellipse.state.angle.degrees)°), y(t) - \(origin.y) = \(b)sin(2πt + \(ellipse.state.angle.degrees)°)")
        }
    }
    
    @objc func addEllipse(vc: EllipseViewController) {
        vc.delegate = self
        vc.blockUndoRedoButtonDelegate = blockUndoRedoButtonDelegate
        self.addChild(vc)
        self.view.addSubview(vc.view)
        vc.didMove(toParent: self)
        self.undoManager?.registerUndo(withTarget: self, selector: #selector(removeEllipse(vc:)), object: vc)
    }
    
    @objc func removeEllipse(vc: EllipseViewController) {
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        self.undoManager?.registerUndo(withTarget: self, selector: #selector(addEllipse(vc:)), object: vc)
    }
    
    func informEllipseWasRemoved(_ controller: EllipseViewController) {
        self.removeEllipse(vc: controller)
    }
    
    func informEllipseWasUpdated(_ controller: EllipseViewController) {
        self.undoManager?.registerUndo(withTarget: controller, selector: #selector(EllipseViewController.undo), object: nil)
    }
    
//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
//        for child in self.children {
//            if let vc = child as? EllipseViewController {
//                if vc.pinchPolicy != .unselected && vc.insideEllipse(touch.location(in: vc.view)) {
//                    return false
//                }
//            }
//        }
//        return true
//    }
    func cancelFitting() {
        logger.info("cancel fitting")
    }
    func resetPinchPolicy() {
        for child in self.children {
            if let vc = child as? EllipseViewController {
                vc.resetEllipsePinchPolicy()
            }
        }
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
}



func lerp(_ x0: CGFloat, _ x1: CGFloat, _ t: CGFloat) -> CGFloat {
    return x0 + (x1 - x0) * t
}

func lerp(_ p0: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
    return CGPoint(x: lerp(p0.x, p1.x, t), y: lerp(p0.y, p1.y, t))
}

func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
    return hypot(end.x - start.x, end.y - start.y)
}

func catmullRomSpline(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let t2 = t * t
    let t3 = t2 * t
    let a = 2 * p1
    let b = p2 - p0
    let c = 2 * p0 - 5 * p1 + 4 * p2 - p3
    let d = -p0 + 3 * p1 - 3 * p2 + p3
    return 0.5 * (a + b * t + c * t2 + d * t3)
}

protocol SceneViewDelegate: AnyObject {
    func fitEllipse(with points: [CGPoint])
    func resetPinchPolicy()
    func cancelFitting()
}

let stayTime: TimeInterval = 0.4

class DrawSceneView: UIView {
    weak var delegate: SceneViewDelegate?
    weak var blockUndoRedoButtonDelegate: BlockUndoRedoButtonDelegate?
    private var points: [CGPoint] = []
    private var panGestureRecognizer: UIPanGestureRecognizer!
    
    private var timer: Timer?
    private var hasFired = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }
    
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch(gesture.state) {
        case .began:
            blockUndoRedoButtonDelegate?.disableUndoRedoButton(who: self)
            points = [point]
            setNeedsDisplay()
            assert(timer == nil && !hasFired)
            timer = Timer.scheduledTimer(timeInterval: stayTime, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: false)
        case .changed:
            points.append(point)
            setNeedsDisplay()
            if !hasFired {
                timer!.invalidate()
                timer = Timer.scheduledTimer(timeInterval: stayTime, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: false)
            } else {
                delegate?.cancelFitting()
            }
        default:
            blockUndoRedoButtonDelegate?.enableUndoRedoButton(who: self)
            points = []
            setNeedsDisplay()
            hasFired = false
            timer?.invalidate()
            timer = nil
            break
        }
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        logger.info("reset pinch policy" )
        delegate?.resetPinchPolicy()
    }

    override func draw(_ rect: CGRect) {
        guard points.count > 1 else { return }
        let path = UIBezierPath()
        path.move(to: points.first!)
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        path.addLine(to: points.first!)
        path.close()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor.black.setStroke()
        UIColor.gray.setFill()
        path.lineWidth = 5
        path.stroke()
        path.fill()
    }
    @objc func handleTimer() {
        logger.log("handleTimer")
        hasFired = true
        delegate?.fitEllipse(with: points)
        setNeedsDisplay()
    }

}

