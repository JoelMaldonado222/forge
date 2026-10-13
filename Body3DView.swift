import SwiftUI
import UIKit
import SceneKit

/// A 3D training figure: a graphite, athletic mannequin where only the
/// muscles you trained glow volt. Built from smooth SceneKit primitives
/// (scaled spheres = ellipsoids, capsules) layered as a base body with
/// muscle "overlays" on top, so the silhouette is continuous and each
/// muscle group can light up on its own.
///
/// Each muscle group owns one shared material, so `intensities` drives the
/// glow per group (0 = unlit grey, 1 = full volt). All colors come from
/// ForgeTheme.
struct Body3DView: UIViewRepresentable {
    /// Normalized highlight per muscle group, 0...1.
    var intensities: [MuscleGroup: Double]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildScene()
        view.backgroundColor = ForgeTheme.sceneBackground
        view.allowsCameraControl = true
        // Lighting is set up by hand in buildScene (key, fill, rim, ambient).
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        // Orbit around the middle of the body, not the feet.
        view.defaultCameraController.target = Coordinator.lookTarget
        context.coordinator.highlight(intensities: intensities)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.highlight(intensities: intensities)
    }

    final class Coordinator {
        static let lookTarget = SCNVector3(x: 0, y: 3.0, z: 0)

        private var materials: [MuscleGroup: SCNMaterial] = [:]
        /// Last applied intensities, so re-renders that don't change the
        /// training data don't touch SceneKit at all.
        private var lastApplied: [MuscleGroup: Double]?

        private let neutralMaterial: SCNMaterial = {
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.diffuse.contents = ForgeTheme.figureNeutral
            material.specular.contents = ForgeTheme.figureNeutralSpecular
            return material
        }()

        private let groundMaterial: SCNMaterial = {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = ForgeTheme.figureGroundShadow
            material.writesToDepthBuffer = false
            return material
        }()

        private func material(for group: MuscleGroup) -> SCNMaterial {
            if let existing = materials[group] { return existing }
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.diffuse.contents = ForgeTheme.figureMuscleColor(0)
            material.specular.contents = ForgeTheme.figureMuscleSpecular
            material.emission.contents = ForgeTheme.voltGlow(0)
            materials[group] = material
            return material
        }

        // MARK: Building blocks

        /// An ellipsoid: a unit sphere stretched by `scale`.
        private func ellipsoid(_ scale: (Float, Float, Float)) -> (SCNGeometry, SCNVector3) {
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 48
            return (sphere, SCNVector3(scale.0, scale.1, scale.2))
        }

        /// Adds one part. `group == nil` means neutral base body.
        @discardableResult
        private func add(
            _ geometry: SCNGeometry,
            _ group: MuscleGroup?,
            at position: SCNVector3,
            scale: SCNVector3 = SCNVector3(1, 1, 1),
            tilt: Float = 0,
            to parent: SCNNode
        ) -> SCNNode {
            geometry.materials = [group.map { material(for: $0) } ?? neutralMaterial]
            let node = SCNNode(geometry: geometry)
            node.name = group?.rawValue
            node.position = position
            node.scale = scale
            node.eulerAngles = SCNVector3(0, 0, tilt)
            parent.addChildNode(node)
            return node
        }

        private func addEllipsoid(_ scale: (Float, Float, Float), _ group: MuscleGroup?, at position: SCNVector3, tilt: Float = 0, to parent: SCNNode) {
            let (geometry, s) = ellipsoid(scale)
            add(geometry, group, at: position, scale: s, tilt: tilt, to: parent)
        }

        private func capsule(radius: CGFloat, height: CGFloat) -> SCNCapsule {
            let capsule = SCNCapsule(capRadius: radius, height: height)
            capsule.radialSegmentCount = 48
            return capsule
        }

        /// A point `distance` down a limb hanging from `start`, tilted
        /// outward by `angle` (radians) on the given side (-1 left, +1 right).
        private func along(_ start: SCNVector3, angle: Float, side: Float, distance: Float) -> SCNVector3 {
            SCNVector3(start.x + sin(angle) * side * distance, start.y - cos(angle) * distance, start.z)
        }

        // MARK: Scene

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            let body = SCNNode()
            body.name = "body"

            buildTorso(on: body)
            buildArms(on: body)
            buildLegs(on: body)

            // Soft contact shadow so the figure stands on something.
            let ground = SCNCylinder(radius: 1.0, height: 0.01)
            ground.materials = [groundMaterial]
            let groundNode = SCNNode(geometry: ground)
            groundNode.position = SCNVector3(0, -0.12, 0.05)
            groundNode.scale = SCNVector3(1, 1, 0.6)
            body.addChildNode(groundNode)

            // Slow idle spin; the user can still orbit with allowsCameraControl.
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 30))
            body.runAction(spin)
            scene.rootNode.addChildNode(body)

            addLights(to: scene.rootNode)

            let cameraNode = SCNNode()
            let camera = SCNCamera()
            camera.fieldOfView = 45
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(x: 0, y: 3.3, z: 8.6)
            scene.rootNode.addChildNode(cameraNode)
            cameraNode.look(at: Self.lookTarget)

            return scene
        }

        private func buildTorso(on body: SCNNode) {
            // Base body (neutral): head, neck, ribcage, waist, pelvis.
            addEllipsoid((0.28, 0.35, 0.31), nil, at: SCNVector3(0, 6.0, 0.03), to: body)
            add(capsule(radius: 0.15, height: 0.55), nil, at: SCNVector3(0, 5.58, -0.02), to: body)
            addEllipsoid((0.84, 0.74, 0.46), nil, at: SCNVector3(0, 4.72, -0.02), to: body)
            addEllipsoid((0.6, 0.62, 0.38), nil, at: SCNVector3(0, 3.92, 0.0), to: body)
            addEllipsoid((0.6, 0.42, 0.39), nil, at: SCNVector3(0, 3.36, -0.02), to: body)

            for side: Float in [-1, 1] {
                // Pecs: wide flat ellipsoids on the upper ribcage.
                addEllipsoid((0.42, 0.29, 0.18), .chest, at: SCNVector3(0.35 * side, 4.97, 0.31), tilt: 0.16 * side, to: body)
                // Traps: slope from the neck to the shoulder.
                addEllipsoid((0.44, 0.17, 0.26), .back, at: SCNVector3(0.34 * side, 5.36, -0.08), tilt: -0.48 * side, to: body)
                // Lats: long wedges down the sides of the back (the V-taper).
                addEllipsoid((0.28, 0.64, 0.24), .back, at: SCNVector3(0.52 * side, 4.4, -0.24), tilt: 0.24 * side, to: body)
                // Glutes.
                addEllipsoid((0.31, 0.33, 0.27), .glutes, at: SCNVector3(0.27 * side, 3.2, -0.22), to: body)
            }
            // Upper back (rhomboids / mid traps).
            addEllipsoid((0.52, 0.44, 0.19), .back, at: SCNVector3(0, 4.9, -0.32), to: body)

            // Abs: six pads plus the obliques at the sides.
            for (row, y) in [Float(4.3), 4.0, 3.7].enumerated() {
                for side: Float in [-1, 1] {
                    addEllipsoid((0.15, 0.135, 0.07), .abs, at: SCNVector3(0.155 * side, y, 0.335 - Float(row) * 0.012), to: body)
                }
            }
            for side: Float in [-1, 1] {
                addEllipsoid((0.15, 0.4, 0.22), .abs, at: SCNVector3(0.44 * side, 3.92, 0.06), tilt: -0.12 * side, to: body)
            }
        }

        private func buildArms(on body: SCNNode) {
            let tiltAngle: Float = 0.16 // slight A-pose
            for side: Float in [-1, 1] {
                let tilt = tiltAngle * side
                let shoulder = SCNVector3(0.95 * side, 5.1, -0.02)
                // Delts: rounded caps over the shoulder joint.
                addEllipsoid((0.3, 0.32, 0.31), .shoulders, at: SCNVector3(0.98 * side, 5.05, 0.0), to: body)

                let upperMid = along(shoulder, angle: tiltAngle, side: side, distance: 0.62)
                let elbow = along(shoulder, angle: tiltAngle, side: side, distance: 1.2)
                add(capsule(radius: 0.16, height: 1.15), nil, at: upperMid, tilt: tilt, to: body)
                addEllipsoid((0.15, 0.4, 0.14), .biceps, at: SCNVector3(upperMid.x, upperMid.y - 0.02, upperMid.z + 0.09), tilt: tilt, to: body)
                addEllipsoid((0.16, 0.44, 0.15), .triceps, at: SCNVector3(upperMid.x + 0.02 * side, upperMid.y + 0.05, upperMid.z - 0.09), tilt: tilt, to: body)
                add(SCNSphere(radius: 0.135), nil, at: elbow, to: body)

                let foreMid = along(elbow, angle: tiltAngle, side: side, distance: 0.5)
                let wrist = along(elbow, angle: tiltAngle, side: side, distance: 0.98)
                add(capsule(radius: 0.12, height: 1.0), nil, at: foreMid, tilt: tilt, to: body)
                addEllipsoid((0.15, 0.36, 0.14), .forearms, at: along(elbow, angle: tiltAngle, side: side, distance: 0.36), tilt: tilt, to: body)
                addEllipsoid((0.09, 0.17, 0.12), nil, at: along(wrist, angle: tiltAngle, side: side, distance: 0.17), tilt: tilt, to: body) // hand
            }
        }

        private func buildLegs(on body: SCNNode) {
            let tiltAngle: Float = -0.03 // feet slightly inward of the hips
            for side: Float in [-1, 1] {
                let tilt = tiltAngle * side
                let hip = SCNVector3(0.31 * side, 3.22, 0.0)
                let thighMid = along(hip, angle: tiltAngle, side: side, distance: 0.78)
                let knee = along(hip, angle: tiltAngle, side: side, distance: 1.56)
                add(capsule(radius: 0.25, height: 1.62), nil, at: thighMid, tilt: tilt, to: body)
                // Quads: the big front teardrop plus the inner bulge above the knee.
                addEllipsoid((0.25, 0.68, 0.2), .quads, at: SCNVector3(thighMid.x + 0.02 * side, thighMid.y + 0.06, 0.12), tilt: tilt, to: body)
                addEllipsoid((0.13, 0.21, 0.13), .quads, at: SCNVector3(knee.x - 0.09 * side, knee.y + 0.33, 0.1), to: body)
                // Hamstrings on the back of the thigh.
                addEllipsoid((0.23, 0.64, 0.18), .hamstrings, at: SCNVector3(thighMid.x, thighMid.y + 0.02, -0.13), tilt: tilt, to: body)
                add(SCNSphere(radius: 0.165), nil, at: SCNVector3(knee.x, knee.y, knee.z + 0.02), to: body)

                let shinMid = along(knee, angle: tiltAngle, side: side, distance: 0.68)
                let ankle = along(knee, angle: tiltAngle, side: side, distance: 1.36)
                add(capsule(radius: 0.15, height: 1.42), nil, at: shinMid, tilt: tilt, to: body)
                // Calves: the diamond on the back of the lower leg.
                addEllipsoid((0.2, 0.42, 0.18), .calves, at: SCNVector3(shinMid.x, shinMid.y + 0.28, -0.09), to: body)
                // Foot.
                addEllipsoid((0.12, 0.09, 0.3), nil, at: SCNVector3(ankle.x, ankle.y - 0.07, 0.13), to: body)
            }
        }

        /// Studio lighting: soft ambient, a warm key from upper-left front,
        /// a cool fill from the right, and a rim light from behind that
        /// outlines the silhouette against the dark background.
        private func addLights(to root: SCNNode) {
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = ForgeTheme.figureAmbientLight
            ambient.intensity = 1000
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            root.addChildNode(ambientNode)

            let directional: [(UIColor, CGFloat, SCNVector3)] = [
                (ForgeTheme.figureKeyLight, 1000, SCNVector3(-4, 8, 7)),
                (ForgeTheme.figureFillLight, 550, SCNVector3(5, 3, 4)),
                (ForgeTheme.figureRimLight, 900, SCNVector3(0, 5, -8)),
            ]
            for (color, intensity, position) in directional {
                let light = SCNLight()
                light.type = .directional
                light.color = color
                light.intensity = intensity
                let node = SCNNode()
                node.light = light
                node.position = position
                node.look(at: Self.lookTarget)
                root.addChildNode(node)
            }
        }

        /// Lights up each muscle group: its surface blends toward volt and it
        /// gets a self-lit glow, both scaled by intensity (0...1).
        func highlight(intensities: [MuscleGroup: Double]) {
            guard intensities != lastApplied else { return }
            lastApplied = intensities
            for group in MuscleGroup.allCases {
                guard let material = materials[group] else { continue }
                let value = intensities[group] ?? 0
                material.diffuse.contents = ForgeTheme.figureMuscleColor(value)
                material.emission.contents = ForgeTheme.voltGlow(value)
            }
        }
    }
}
