package ai.clomni.messenger.ui

import androidx.core.content.FileProvider

/**
 * Hands the camera app the file it writes a photo or a video into ([Attachments.cameraTarget]; authority
 * `<applicationId>.clomni.camera`, paths `@xml/clomni_camera_paths`).
 *
 * The SDK's own class, not androidx's: the manifest merger knows a `<provider>` by its class name, so a library that
 * declares `androidx.core.content.FileProvider` itself stops every app that also has another one with a different
 * authority (CM-185: unity-webview's `<applicationId>.unitywebview.fileprovider` in a Unity game). The app's own fix,
 * `tools:replace`, would keep one authority and leave the other provider's files unreachable.
 */
internal class ClomniFileProvider : FileProvider()
