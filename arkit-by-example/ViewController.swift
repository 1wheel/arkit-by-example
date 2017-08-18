//
//  ViewController.swift
//  arkit-by-example
//
//  Created by Arnaud Pasquelin on 03/07/2017.
//  Copyright © 2017 Arnaud Pasquelin. All rights reserved.
//

import UIKit
import SceneKit
import ARKit

struct CollisionCategory: OptionSet{
    let rawValue: Int
    
    static let bottom = CollisionCategory(rawValue: 1 << 0)
    static let cube = CollisionCategory(rawValue: 1 << 1)
}

class ViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    
    // A dictionary of all the current planes being rendered in the scene
    var planes: [UUID:Plane] = [:]
    
    var boxes: [SCNNode] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupScene()
        self.setupRecognizers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.setupSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func setupScene() {
        // Setup the ARSCNViewDelegate - this gives us callbacks to handle new
        // geometry creation
        self.sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        self.sceneView.showsStatistics = true
        self.sceneView.autoenablesDefaultLighting = true
        
        // Turn on debug options to show the world origin and also render all
        // of the feature points ARKit is tracking
        // self.sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin, ARSCNDebugOptions.showFeaturePoints]
        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]

        // Container to hold all of the 3D geometry
        let scene = SCNScene()
        // Set the scene to the view
        self.sceneView.scene = scene
    }
    
    func setupSession() {
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    func setupRecognizers(){
        // single tap adds geometry
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapFrom))
        tapGestureRecognizer.numberOfTapsRequired = 1
        self.sceneView.addGestureRecognizer(tapGestureRecognizer)
        
    }
    
    @objc func handleTapFrom(recognizer: UITapGestureRecognizer){
        let tapPoint = recognizer.location(in: self.sceneView)
        let result = self.sceneView.hitTest(tapPoint, types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        
        print("result.count", result.count)
        if result.count == 0{
            return
        }
        
        let hitResult = result.first
        self.insertGeometry(hitResult: hitResult!)
    }
    
    func insertGeometry(hitResult: ARHitTestResult){
        print("inserting cube")
        let dimension: CGFloat = 0.1
        let cube = SCNBox(width: dimension, height: dimension, length: dimension, chamferRadius: 0)
        let node = SCNNode(geometry: cube)
        
        node.physicsBody = SCNPhysicsBody(type: SCNPhysicsBodyType.dynamic, shape: nil)
        node.physicsBody?.mass = 2.0
        node.physicsBody?.categoryBitMask = CollisionCategory.cube.rawValue
        
        let insertionYOffset: Float = 0.5
        node.position = SCNVector3Make(hitResult.worldTransform.columns.3.x, hitResult.worldTransform.columns.3.y.advanced(by: insertionYOffset),hitResult.worldTransform.columns.3.z)
        self.sceneView.scene.rootNode.addChildNode(node)
        self.boxes.append(node)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if !anchor.isKind(of: ARPlaneAnchor.classForCoder()) {
            print("found non plane anchor")
            return
        }
        
        // When a new plane is detected we create a new SceneKit plane to visualize it in 3D
        print("found plane")
        let plane = Plane(anchor: anchor as! ARPlaneAnchor, isHidden: false)
        planes[anchor.identifier] = plane
        node.addChildNode(plane)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let plane = planes[anchor.identifier] else {
            return
        }
        
        // When an anchor is updated we need to also update our 3D geometry too. For example
        // the width and height of the plane detection may have changed so we need to update
        // our SceneKit geometry to match that
        plane.update(anchor: anchor as! ARPlaneAnchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // Nodes will be removed if planes multiple individual planes that are detected to all be
        // part of a larger plane are merged.
        self.planes.removeValue(forKey: anchor.identifier)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
}
