import simd

enum MotionCoordinateAdapter {
    /// Core Motion attitude uses the inverse of the protocol's active
    /// device-to-reference convention. Unit-quaternion inversion negates the
    /// vector part and retains the scalar part.
    static func deviceToReferenceQuaternion(_ coreMotion: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(-coreMotion.x, -coreMotion.y, -coreMotion.z, coreMotion.w)
    }
}

