import simd

enum MotionCoordinateAdapter {
    /// Core Motion attitude already rotates device axes into its reference
    /// frame (upright portrait reports pitch +90°, mapping +Y_D to +Z), which
    /// is the protocol's device-to-reference convention. Pass it through.
    static func deviceToReferenceQuaternion(_ coreMotion: SIMD4<Float>) -> SIMD4<Float> {
        coreMotion
    }
}
