import SwiftUI
import UIKit
import SceneKit

/// An anatomical 3D training figure built from SceneKit primitives, styled
/// after muscle-chart references: a matte grey physique where ONLY trained
/// muscles glow volt — everything else stays neutral grey.
/// Each muscle group owns a shared material, so `intensities` drives the
/// volt glow per group (0 = unlit grey, 1 = full volt).
struct Body3DView: UIViewRepresentable {
    /// Normalized highlight per muscle group, 0...1.
    var intensities: [MuscleGroup: Double]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildScene()
        view.backgroundColor = ForgeTheme.sceneBackground
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        context.coordinator.highlight(intensities: intensities)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.highlight(intensities: intensities)
    }

    final class Coordinator {
        private var materials: [MuscleGroup: SCNMaterial] = [:]
        /// Last applied intensities, so re-renders that don't change the
        /// training data don't touch SceneKit at all.
        private var lastApplied: [MuscleGroup: Double]?

        private let neutralMaterial: SCNMaterial = {
            let material = SCNMaterial()
            material.diffuse.contents = ForgeTheme.figureNeutral
            material.specular.contents = ForgeTheme.figureNeutralSpecular
            return material
        }()

        private func material(for group: MuscleGroup) -> SCNMaterial {
            if let existing = materials[group] { return existing }
            let material = SCNMaterial()
            material.diffuse.contents = ForgeTheme.figureMuscle
            material.specular.contents = ForgeTheme.figureMuscleSpecular
            material.emission.contents = ForgeTheme.voltGlow(0)
            materials[group] = material
            return material
        }

        private func muscleNode(_ group: MuscleGroup, geometry: SCNGeometry, x: Float, y: Float, z: Float) -> SCNNode {
            geometry.materials = [material(for: group)]
            let node = SCNNode(geometry: geometry)
            node.name = group.rawValue
            node.position = SCNVector3(x: x, y: y, z: z)
            return node
        }

        private func neutralNode(geometry: SCNGeometry, x: Float, y: Float, z: Float) -> SCNNode {
            geometry.materials = [neutralMaterial]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x: x, y: y, z: z)
            return node
        }

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            let body = SCNNode()
            body.name = "body"

            // Head & neck (neutral)
            body.addChildNode(neutralNode(geometry: SCNSphere(radius: 0.34), x: 0, y: 5.72, z: 0))
            body.addChildNode(neutralNode(geometry: SCNCylinder(radius: 0.15, height: 0.45), x: 0, y: 5.32, z: 0))

            // Trapezius slope: angled boxes from the neck out to the delts.
            for side: Float in [-1, 1] {
                let trap = muscleNode(
                    .shoulders,
                    geometry: SCNBox(width: 1.05, height: 0.38, length: 0.58, chamferRadius: 0.12),
                    x: 0.72 * side, y: 5.08, z: -0.04
                )
                trap.eulerAngles = SCNVector3(0, 0, -0.36 * side)
                body.addChildNode(trap)
            }

            // Chest: broad torso plus defined pecs up front.
            body.addChildNode(muscleNode(.chest, geometry: SCNBox(width: 2.5, height: 1.45, length: 0.9, chamferRadius: 0.2), x: 0, y: 4.3, z: 0.1))
            for side: Float in [-1, 1] {
                body.addChildNode(muscleNode(.chest, geometry: SCNSphere(radius: 0.52), x: 0.62 * side, y: 4.38, z: 0.48))
            }

            // Back: wide rear torso plus flared lats for the V-taper.
            body.addChildNode(muscleNode(.back, geometry: SCNBox(width: 2.3, height: 1.45, length: 0.5, chamferRadius: 0.15), x: 0, y: 4.3, z: -0.38))
            for side: Float in [-1, 1] {
                let lat = muscleNode(
                    .back,
                    geometry: SCNBox(width: 0.5, height: 1.05, length: 0.45, chamferRadius: 0.12),
                    x: 0.98 * side, y: 3.55, z: -0.32
                )
                lat.eulerAngles = SCNVector3(0, 0, -0.26 * side)
                body.addChildNode(lat)
            }

            // Abs: segmented upper/lower blocks for definition, tapered waist.
            body.addChildNode(muscleNode(.abs, geometry: SCNBox(width: 1.5, height: 0.68, length: 0.8, chamferRadius: 0.14), x: 0, y: 3.32, z: 0.1))
            body.addChildNode(muscleNode(.abs, geometry: SCNBox(width: 1.38, height: 0.62, length: 0.78, chamferRadius: 0.14), x: 0, y: 2.68, z: 0.1))
            body.addChildNode(neutralNode(geometry: SCNBox(width: 1.7, height: 0.6, length: 0.85, chamferRadius: 0.14), x: 0, y: 2.05, z: 0)) // pelvis

            // Shoulders & arms.
            for side: Float in [-1, 1] {
                body.addChildNode(muscleNode(.shoulders, geometry: SCNSphere(radius: 0.4), x: 1.42 * side, y: 4.88, z: 0))
                body.addChildNode(muscleNode(.biceps, geometry: SCNCapsule(capRadius: 0.24, height: 0.85), x: 1.5 * side, y: 4.02, z: 0.18))
                body.addChildNode(muscleNode(.biceps, geometry: SCNSphere(radius: 0.26), x: 1.5 * side, y: 4.28, z: 0.18)) // peak
                body.addChildNode(muscleNode(.triceps, geometry: SCNCapsule(capRadius: 0.24, height: 0.85), x: 1.5 * side, y: 4.02, z: -0.2))
                body.addChildNode(muscleNode(.forearms, geometry: SCNCapsule(capRadius: 0.19, height: 0.8), x: 1.5 * side, y: 3.02, z: 0))
                body.addChildNode(neutralNode(geometry: SCNSphere(radius: 0.15), x: 1.5 * side, y: 2.44, z: 0)) // hand
            }

            // Hips & legs.
            for side: Float in [-1, 1] {
                body.addChildNode(muscleNode(.glutes, geometry: SCNSphere(radius: 0.4), x: 0.5 * side, y: 1.88, z: -0.4))
                body.addChildNode(muscleNode(.quads, geometry: SCNCapsule(capRadius: 0.31, height: 1.1), x: 0.5 * side, y: 1.02, z: 0.2))
                body.addChildNode(muscleNode(.quads, geometry: SCNSphere(radius: 0.3), x: 0.5 * side, y: 0.48, z: 0.24)) // teardrop
                body.addChildNode(muscleNode(.hamstrings, geometry: SCNCapsule(capRadius: 0.29, height: 1.1), x: 0.5 * side, y: 1.02, z: -0.24))
                body.addChildNode(muscleNode(.calves, geometry: SCNCapsule(capRadius: 0.22, height: 0.72), x: 0.5 * side, y: -0.02, z: -0.08))
                body.addChildNode(muscleNode(.calves, geometry: SCNSphere(radius: 0.25), x: 0.5 * side, y: 0.2, z: -0.1)) // gastroc
                body.addChildNode(neutralNode(geometry: SCNBox(width: 0.34, height: 0.16, length: 0.7, chamferRadius: 0.05), x: 0.5 * side, y: -0.6, z: 0.12)) // foot
            }

            // Slow idle spin; the user can still orbit with allowsCameraControl.
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 26))
            body.runAction(spin)

            scene.rootNode.addChildNode(body)

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 2.8, z: 10)
            scene.rootNode.addChildNode(cameraNode)
            cameraNode.look(at: SCNVector3(x: 0, y: 2.5, z: 0))

            return scene
        }

        /// Sets the volt emissive glow per muscle group. Values are clamped
        /// to 0...1; untrained groups stay matte grey.
        func highlight(intensities: [MuscleGroup: Double]) {
            guard intensities != lastApplied else { return }
            lastApplied = intensities
            for group in MuscleGroup.allCases {
                guard let material = materials[group] else { continue }
                material.emission.contents = ForgeTheme.voltGlow(intensities[group] ?? 0)
            }
        }
    }
}
