package org.krak_en.voice

import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Xml
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import java.util.zip.ZipFile

/** Text extraction is local, bounded, and never executes document macros. */
class DocumentTextHandler {
    private val main = Handler(Looper.getMainLooper())
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "extract") { result.notImplemented(); return }
        val path = call.argument<String>("path")
        if (path == null) { result.error("DOCUMENT_ERROR", "No document selected.", null); return }
        worker.execute {
            try {
                val file = File(path)
                check(file.isFile && file.length() in 1..MAX_FILE) { "Choose a non-empty document smaller than 50 MB." }
                val data = when (file.extension.lowercase(Locale.ROOT)) {
                    "pdf" -> extractPdf(file)
                    "docx" -> extractDocx(file)
                    else -> error("Choose a PDF or Word .docx document. Save older .doc files as .docx first.")
                }
                check((data["text"] as String).isNotBlank()) { "No readable text was found. Scanned PDFs and images need OCR before importing." }
                main.post { result.success(data) }
            } catch (e: Exception) {
                val message = if (e is SecurityException) "This document is password-protected. Import an unlocked copy."
                    else e.message ?: "Unable to read this document. Try exporting a new PDF or .docx copy."
                main.post { result.error("DOCUMENT_ERROR", message, null) }
            }
        }
    }
    private fun extractPdf(file: File): Map<String, Any> {
        check(Build.VERSION.SDK_INT >= 35) { "PDF text import requires Android 15 or later." }
        val text = StringBuilder()
        var emptyPages = 0
        var pages: Int
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { pdf ->
                pages = pdf.pageCount
                check(pages in 1..200) { "Import a PDF with 1–200 pages, or split it into smaller documents." }
                for (i in 0 until pages) {
                    pdf.openPage(i).use { page ->
                        val pageText = page.textContents.joinToString("\n") { it.text }.trim()
                        if (pageText.isEmpty()) emptyPages++
                        else text.append(pageText).append("\n\n")
                        check(text.length <= MAX_TEXT) { "This document contains too much text. Split it into smaller documents." }
                    }
                }
            }
        }
        val warning = if (emptyPages > 0) "$emptyPages of $pages pages have no readable text. They may be blank or scanned; summaries include extracted text only." else ""
        return mapOf("text" to text.toString().trim(), "warning" to warning)
    }
    private fun extractDocx(file: File): Map<String, Any> {
        val text = StringBuilder()
        ZipFile(file).use { zip ->
            val entry = zip.getEntry("word/document.xml") ?: error("This is not a readable Word .docx document.")
            check(entry.size in 1..MAX_XML) { "This Word document is too large to extract. Split it into smaller files." }
            zip.getInputStream(entry).use { input ->
                // Read one bounded XML part, never unzip paths onto disk.
                val xml = input.readBytesLimited(MAX_XML.toInt())
                val parser = Xml.newPullParser()
                parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
                parser.setInput(xml.inputStream(), null)
                var inText = false
                var deletedDepth = 0
                while (true) {
                    val event = parser.nextToken()
                    if (event == XmlPullParser.END_DOCUMENT) break
                    check(event != XmlPullParser.DOCDECL) { "Documents containing XML document declarations are not supported." }
                    val word = parser.namespace == "http://schemas.openxmlformats.org/wordprocessingml/2006/main" ||
                        parser.namespace == "http://purl.oclc.org/ooxml/wordprocessingml/main"
                    if (event == XmlPullParser.START_TAG && word) {
                        when (parser.name) {
                            "del" -> deletedDepth++
                            "t" -> inText = deletedDepth == 0
                            "tab" -> if (deletedDepth == 0) text.append('\t')
                            "br", "cr" -> if (deletedDepth == 0) text.append('\n')
                        }
                    } else if (event == XmlPullParser.END_TAG && word) {
                        when (parser.name) {
                            "del" -> deletedDepth--
                            "t" -> inText = false
                            "p", "tr" -> if (deletedDepth == 0) text.append('\n')
                            "tc" -> if (deletedDepth == 0) text.append('\t')
                        }
                    } else if ((event == XmlPullParser.TEXT || event == XmlPullParser.CDSECT || event == XmlPullParser.ENTITY_REF) && inText) {
                        text.append(parser.text ?: "")
                    }
                    check(text.length <= MAX_TEXT) { "This document contains too much text. Split it into smaller documents." }
                }
            }
        }
        return mapOf("text" to text.toString().trim(), "warning" to "Word import includes body text and tables. Images, comments, headers, footers and footnotes are not included.")
    }
    private fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = read(buffer)
            if (n < 0) break
            check(output.size() + n <= limit) { "The Word document expands beyond the import limit." }
            output.write(buffer, 0, n)
        }
        return output.toByteArray()
    }
    companion object {
        private val worker = Executors.newSingleThreadExecutor()
        private const val MAX_FILE = 50L * 1024 * 1024
        private const val MAX_XML = 8L * 1024 * 1024
        private const val MAX_TEXT = 500000
    }
}
