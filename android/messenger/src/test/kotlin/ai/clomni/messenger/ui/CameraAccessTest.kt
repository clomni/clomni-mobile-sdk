package ai.clomni.messenger.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** G-10 (test report): the attachment sheet had no camera. When it offers one, and when it asks first. */
class CameraAccessTest {
    @Test
    fun theCameraIsOfferedWhereverThereIsOne() {
        assertEquals("no camera, no rows", CameraAccess.NONE, CameraAccess.of(hasCamera = false, declaresCamera = true))
        assertEquals(
            "an app that declares no CAMERA: the camera app takes it, nothing to ask",
            CameraAccess.FREE,
            CameraAccess.of(hasCamera = true, declaresCamera = false),
        )
        assertEquals(
            "an app that declares CAMERA: Android requires it granted first",
            CameraAccess.ASK,
            CameraAccess.of(hasCamera = true, declaresCamera = true),
        )
    }
}
