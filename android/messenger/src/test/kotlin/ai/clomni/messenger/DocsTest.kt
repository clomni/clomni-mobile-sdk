package ai.clomni.messenger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * "The code in the documentation compiles unchanged": every Kotlin and Java block of docs/integration.md names the
 * sample file and lines it was cut from (`<!-- sample: path#L7-L16 -->`), and they must still be those lines. The
 * sample itself is compiled by CI (`:sample:assembleDebug`).
 */
class DocsTest {
    private val android = File(System.getProperty("clomni.android.dir") ?: error("run through Gradle"))
    private val marker = Regex("""<!-- sample: (\S+)#L(\d+)-L(\d+) -->\n```(\w+)\n(.*?)\n```""", RegexOption.DOT_MATCHES_ALL)

    @Test
    fun everyBlockIsTheSamplesCode() {
        val doc = File(android, "docs/integration.md").readText()
        val blocks = marker.findAll(doc).toList()
        val code = Regex("```(kotlin|java)\n").findAll(doc).count()
        assertEquals("every Kotlin and Java block says where in the sample it comes from", code, blocks.size)
        assertTrue(blocks.size >= 10)
        for (block in blocks) {
            val (path, first, last, _, text) = block.destructured
            val lines = File(android, "sample/src/main/$path").readLines().subList(first.toInt() - 1, last.toInt())
            val indent = lines.filter { it.isNotBlank() }.minOf { it.length - it.trimStart().length }
            assertEquals("$path#L$first-L$last", lines.joinToString("\n") { it.drop(indent) }, text)
        }
    }

    /** docs/screenshots/appearance/android are copies of AppearanceSnapshotTest's references, kept the same. */
    @Test
    fun appearanceScreenshotsAreTheSnapshots() {
        val docs = File(android, "../docs/screenshots/appearance/android")
        val prefix = "ai.clomni.messenger.ui_AppearanceSnapshotTest_"
        val references = File(android, "messenger/src/test/snapshots/images").listFiles()!!
            .filter { it.name.startsWith(prefix) }
            .associateBy { it.name.removePrefix(prefix).substringAfter('_') }
        assertEquals(references.keys.sorted(), docs.list()!!.sorted())
        for ((name, reference) in references) {
            assertTrue("docs/screenshots/appearance/android/$name is not the snapshot", reference.readBytes().contentEquals(File(docs, name).readBytes()))
        }
    }
}
