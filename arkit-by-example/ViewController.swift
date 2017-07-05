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

struct CollisionCategory: OptionSet {
    let rawValue: Int
    
    static let bottom = CollisionCategory(rawValue: 1 << 0)
    static let cube = CollisionCategory(rawValue: 1 << 1)
}

class ViewController: UIViewController, ARSCNViewDelegate, UIGestureRecognizerDelegate, SCNPhysicsContactDelegate {
    
    @IBOutlet var sceneView: ARSCNView!
    
    // A dictionary of all the current planes being rendered in the scene
    var planes: [UUID:Plane] = [:]
    // Contains a list of all the boxes rendered in the scene
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
        self.sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin, ARSCNDebugOptions.showFeaturePoints]
        
        // Container to hold all of the 3D geometry
        let scene = SCNScene()
        // Set the scene to the view
        self.sceneView.scene = scene
        
        // For our physics interactions, we place a large node a couple of meters below the world
        // origin, after an explosion, if the geometry we added has fallen onto this surface which
        // is place way below all of the surfaces we would have detected via ARKit then we consider
        // this geometry to have fallen out of the world and remove it
        let bottomPlane = SCNBox(width: 1000, height: 0.5, length: 1000, chamferRadius: 0)
        let bottomMaterial = SCNMaterial()
        bottomMaterial.diffuse.contents = UIColor(white: 1.0, alpha: 0)
        bottomPlane.materials = [bottomMaterial]
        let bottomNode = SCNNode(geometry: bottomPlane)
        bottomNode.position = SCNVector3Make(0, -10, 0)
        bottomNode.physicsBody = SCNPhysicsBody(type: SCNPhysicsBodyType.kinematic, shape: nil)
        bottomNode.physicsBody?.categoryBitMask = CollisionCategory.bottom.rawValue
        bottomNode.physicsBody?.contactTestBitMask = CollisionCategory.cube.rawValue
        self.sceneView.scene.rootNode.addChildNode(bottomNode)
        self.sceneView.scene.physicsWorld.contactDelegate = self
    }
    
    func setupSession() {
        // Create a session configuration
        let configuration = ARWorldTrackingSessionConfiguration()
        
        // Specify that we do want to track horizontal planes. Setting this will cause the ARSCNViewDelegate
        // methods to be called when scenes are detected
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    func setupRecognizers() {
        // Single tap will insert a new piece of geometry into the scene
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapFrom))
        tapGestureRecognizer.numberOfTapsRequired = 1
        self.sceneView.addGestureRecognizer(tapGestureRecognizer)
        
        // Press and hold will cause an explosion causing geometry in the local vicinity of the explosion to move
        let explosionGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldFrom))
        explosionGestureRecognizer.minimumPressDuration = 0.5
        self.sceneView.addGestureRecognizer(explosionGestureRecognizer)
        
        let hidePlanesGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleHidePlaneFrom))
        hidePlanesGestureRecognizer.minimumPressDuration = 1
        hidePlanesGestureRecognizer.numberOfTouchesRequired = 2
        self.sceneView.addGestureRecognizer(hidePlanesGestureRecognizer)
    }
    
    @objc func handleTapFrom(recognizer: UITapGestureRecognizer) {
        // Take the screen space tap coordinates and pass them to the hitTest method on the ARSCNView instance
        let tapPoint = recognizer.location(in: self.sceneView)
        let result = self.sceneView.hitTest(tapPoint, types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        
        // If the intersection ray passes through any plane geometry they will be returned, with the planes
        // ordered by distance from the camera
        if result.count == 0 {
            return
        }
        
        // If there are multiple hits, just pick the closest plane
        let hitResult = result.first
        self.insertGeometry(hitResult: hitResult!)
    }
    
    @objc func handleHoldFrom(recognizer: UILongPressGestureRecognizer) {
        if recognizer.state != UIGestureRecognizerState.began {
            return
        }
        
        // Perform a hit test using the screen coordinates to see if the user pressed on
        // a plane.
        let holdPoint = recognizer.location(in: self.sceneView)
        let result = self.sceneView.hitTest(holdPoint, types: ARHitTestResult.ResultType.existingPlaneUsingExtent)
        if result.count == 0 {
            return
        }
        
        let hitResult = result.first
        DispatchQueue.main.async(execute: {
            self.explode(hitResult: hitResult!)
        })
    }
    
    @objc func handleHidePlaneFrom(recognizer: UILongPressGestureRecognizer) {
        if recognizer.state != UIGestureRecognizerState.began {
            return
        }
        
        // Hide all the planes
        for (planeID, _) in self.planes {
            self.planes[planeID]?.hide()
        }
        
        // Stop detecting new planes or updating existing ones.
        let configuration = self.sceneView.session.configuration as! ARWorldTrackingSessionConfiguration
        configuration.planeDetection = ARWorldTrackingSessionConfiguration.PlaneDetection(rawValue: 0)
        self.sceneView.session.run(configuration)
    }
    
    func explode(hitResult: ARHitTestResult) {
        // For an explosion, we take the world position of the explosion and the position of each piece of geometry
        // in the world. We then take the distance between those two points, the closer to the explosion point the
        // geometry is the stronger the force of the explosion.
        
        // The hitResult will be a point on the plane, we move the explosion down a little bit below the
        // plane so that the goemetry fly upwards off the plane
        let explosionYOffset: Float = 0.1
        
        let position = SCNVector3Make(hitResult.worldTransform.columns.3.x, hitResult.worldTransform.columns.3.y.advanced(by: -explosionYOffset), hitResult.worldTransform.columns.3.z)
        
        // We need to find all of the geometry affected by the explosion, ideally we would have some
        // spatial data structure like an octree to efficiently find all geometry close to the explosion
        // but since we don't have many items, we can just loop through all of the current geometry
        for cubeNode in self.boxes {
            // The distance between the explosion and the geometry
            var distance = SCNVector3Make(cubeNode.worldPosition.x - position.x, cubeNode.worldPosition.y - position.y, cubeNode.worldPosition.z - position.z)
            let length: Float = sqrtf(distance.x * distance.x + distance.y * distance.y + distance.z * distance.z)
            
            // Set the maximum distance that the explosion will be felt, anything further than 2 meters from
            // the explosion will not be affected by any forces
            let maxDistance: Float = 2
            var scale = max(0, maxDistance - length)
            
            // Scale the force of the explosion
            scale = scale * scale * 2
            
            // Scale the distance vector to the appropriate scale
            distance.x = distance.x / length * scale
            distance.y = distance.y / length * scale
            distance.z = distance.z / length * scale
            
            // Apply a force to the geometry. We apply the force at one of the corners of the cube
            // to make it spin more, vs just at the center
            cubeNode.physicsBody?.applyForce(distance, at: SCNVector3Make(0.05, 0.05, 0.05), asImpulse: true)
        }
    }
    
    func insertGeometry(hitResult: ARHitTestResult) {
        // Right now we just insert a simple cube, later we will improve these to be more
        // interesting and have better texture and shading
        let dimension: CGFloat = 0.1
        let cube = SCNBox(width: dimension, height: dimension, length: dimension, chamferRadius: 0)
        let node = SCNNode(geometry: cube)
        
        // The physicsBody tells SceneKit this geometry should be manipulated by the physics engine
        node.physicsBody = SCNPhysicsBody(type: SCNPhysicsBodyType.dynamic, shape: nil)
        node.physicsBody?.mass = 2.0
        node.physicsBody?.categoryBitMask = CollisionCategory.cube.rawValue
        
        // We insert the geometry slightly above the point the user tapped, so that it drops onto the plane
        // using the physics engine
        let insertionYOffset: Float = 0.5
        node.position = SCNVector3Make(hitResult.worldTransform.columns.3.x, hitResult.worldTransform.columns.3.y.advanced(by: insertionYOffset), hitResult.worldTransform.columns.3.z)
        self.sceneView.scene.rootNode.addChildNode(node)
        self.boxes.append(node)
    }
    
    // MARK: - SCNPhysicsContactDelegate
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // Here we detect a collision between pieces of geometry in the world, if one of the pieces
        // of geometry is the bottom plane it means the geometry has fallen out of the world. just remove it
        guard let physicsBodyA = contact.nodeA.physicsBody, let physicsBodyB = contact.nodeB.physicsBody else {
            return
        }
        
        let categoryA = CollisionCategory.init(rawValue: physicsBodyA.categoryBitMask)
        let categoryB = CollisionCategory.init(rawValue: physicsBodyB.categoryBitMask)
        
        let contactMask: CollisionCategory? = [categoryA, categoryB]
        
        if contactMask == [CollisionCategory.bottom, CollisionCategory.cube] {
            if categoryA == CollisionCategory.bottom {
                contact.nodeB.removeFromParentNode()
            } else {
                contact.nodeA.removeFromParentNode()
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if !anchor.isKind(of: ARPlaneAnchor.classForCoder()) {
            return
        }
        
        // When a new plane is detected we create a new SceneKit plane to visualize it in 3D
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
