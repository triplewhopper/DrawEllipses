//
//  ViewController.swift
//  DrawEllipses
//
//  Created by jsr on 2024/7/19.
//

import UIKit

class EditorViewController: UIViewController, BlockUndoRedoButtonDelegate {

    var scene: DrawSceneViewController!
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var redoButton: UIButton!
    
    var actives: [AnyObject] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("\(self.view)")
        // Do any additional setup after loading the view.
    }
    
    @IBAction func performUndo(_ sender: UIButton) {
        scene.undo()
    }
    
    @IBAction func performRedo(_ sender: UIButton) {
        scene.redo()
    }
    
    func disableUndoRedoButton(who: AnyObject) {
        actives.append(who)
        logger.info("disableUndoRedoButton: \(who.description)")
        undoButton.isEnabled = false
        redoButton.isEnabled = false
    }
    
    func enableUndoRedoButton(who: AnyObject) {
        logger.info("enableUndoRedoButton: \(who.description)")
        let i = actives.firstIndex(where: { $0 === who })!
        actives.remove(at: i)
        if actives.isEmpty {
            undoButton.isEnabled = true
            redoButton.isEnabled = true
        }
    }
    
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if let sceneVC = segue.destination as? DrawSceneViewController {
            scene = sceneVC
            scene.blockUndoRedoButtonDelegate = self
        }
    }
    

}


