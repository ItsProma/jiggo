package net.debcreatives.jiggo

import android.app.Activity
import android.content.Intent
import android.content.ClipData
import androidx.core.content.FileProvider
import java.io.File
import android.provider.Settings
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingOpenLimit = 128 * 1024
    private val docxMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    private val textOpenRequestCode = 49292
    private var pendingTextOpen: MethodChannel.Result? = null
    private val pdfRequestCode = 49291
    private var pendingPdf: ByteArray? = null
    private var pendingPdfResult: MethodChannel.Result? = null

    private fun imageMime(bytes: ByteArray?, name: String?): String? {
        if (bytes == null || name == null) return null
        if (name.endsWith(".png", ignoreCase = true) && bytes.size >= 8 &&
            bytes.copyOfRange(0, 8).contentEquals(byteArrayOf(0x89.toByte(), 80, 78, 71, 13, 10, 26, 10))) return "image/png"
        if ((name.endsWith(".jpg", ignoreCase = true) || name.endsWith(".jpeg", ignoreCase = true)) && bytes.size >= 3 &&
            (bytes[0].toInt() and 255) == 255 && (bytes[1].toInt() and 255) == 216 && (bytes[2].toInt() and 255) == 255) return "image/jpeg"
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jiggo/pdf_files")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareDocx" || call.method == "shareImage") {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("filename")
                    val picture = call.method == "shareImage"
                    val mime = if (picture) imageMime(bytes, name) else docxMime
                    val limit = if (picture) 32 * 1024 * 1024 else 2 * 1024 * 1024
                    if (bytes == null || bytes.size < 4 || bytes.size > limit || mime == null ||
                        (!picture && (bytes[0] != 0x50.toByte() || bytes[1] != 0x4b.toByte())) ||
                        name.isNullOrBlank() || (!picture && !name.endsWith(".docx")) || name.length > 200 ||
                        name.any { it == '/' || it == '\\' || it.code < 32 }) {
                        result.error("invalid", "Invalid share file.", null)
                    } else {
                        Thread {
                            try {
                                val root = File(cacheDir, "docx_share").apply { mkdirs() }
                                val old = root.listFiles()?.sortedByDescending { it.lastModified() } ?: emptyList()
                                var retained = bytes.size.toLong()
                                old.forEachIndexed { index, file ->
                                    val size = if (file.isDirectory) file.listFiles()?.sumOf { it.length() } ?: 0L else file.length()
                                    if (index >= 7 || file.lastModified() < System.currentTimeMillis() - 86400000 || retained + size > 48L * 1024 * 1024) {
                                        file.deleteRecursively()
                                    } else retained += size
                                }
                                val folder = File(root, java.util.UUID.randomUUID().toString()).apply { mkdirs() }
                                val file = File(folder, name)
                                file.writeBytes(bytes)
                                val uri = FileProvider.getUriForFile(this, "$packageName.docxfiles", file)
                                runOnUiThread {
                                    try {
                                        val send = Intent(Intent.ACTION_SEND).apply {
                                            type = mime
                                            putExtra(Intent.EXTRA_STREAM, uri)
                                            clipData = ClipData.newUri(contentResolver, name, uri)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        }
                                        startActivity(Intent.createChooser(send, null))
                                        result.success(true)
                                    } catch (_: Exception) { result.error("unavailable", "Unable to share the file.", null) }
                                }
                            } catch (_: Exception) {
                                runOnUiThread { result.error("write-failed", "Unable to prepare file sharing.", null) }
                            }
                        }.start()
                    }
                } else if (call.method == "openText" || call.method == "openDocx" || call.method == "openPdf") {
                    if (pendingTextOpen != null) {
                        result.error("busy", "A file picker is already open.", null)
                    } else {
                        pendingTextOpen = result
                        val docx = call.method == "openDocx"
                        val pdf = call.method == "openPdf"
                        pendingOpenLimit = if (pdf) 10 * 1024 * 1024 else if (docx) 2 * 1024 * 1024 else 128 * 1024
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (pdf) "application/pdf" else if (docx) docxMime else "text/plain"
                            }, textOpenRequestCode)
                        } catch (_: Exception) {
                            pendingTextOpen = null
                            result.error("unavailable", "Unable to open text file.", null)
                        }
                    }
                } else if (call.method == "shareText") {
                    val text = call.argument<String>("text")
                    val title = call.argument<String>("title") ?: "Jiggo"
                    if (text.isNullOrBlank() || text.length > 20000 || title.length > 150) {
                        result.error("invalid", "Invalid text.", null)
                    } else {
                        try {
                            startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                                putExtra(Intent.EXTRA_SUBJECT, title)
                            }, null))
                            result.success(true)
                        } catch (_: Exception) { result.error("unavailable", "Unable to share text.", null) }
                    }
                } else if (call.method != "savePdf" && call.method != "saveText" && call.method != "saveDocx" && call.method != "saveImage") {
                    result.notImplemented()
                } else if (pendingPdfResult != null) {
                    result.error("busy", "A save dialog is already open.", null)
                } else {
                    val bytes = call.argument<ByteArray>("bytes")
                    val filename = call.argument<String>("filename")
                    val textFile = call.method == "saveText"
                    val docxFile = call.method == "saveDocx"
                    val imageFile = call.method == "saveImage"
                    val pictureMime = if (imageFile) imageMime(bytes, filename) else null
                    if (bytes == null || bytes.isEmpty() || bytes.size > 32 * 1024 * 1024 ||
                        (textFile && bytes.size > 128 * 1024) ||
                        (docxFile && (bytes.size < 4 || bytes.size > 2 * 1024 * 1024 || bytes[0] != 0x50.toByte() || bytes[1] != 0x4b.toByte() || filename?.endsWith(".docx") != true)) ||
                        (imageFile && pictureMime == null) ||
                        (!textFile && !docxFile && !imageFile && (bytes.size < 5 || String(bytes.copyOfRange(0, 5), Charsets.US_ASCII) != "%PDF-")) ||
                        filename.isNullOrBlank() || filename.length > 200 ||
                        filename.any { it == '/' || it == '\\' || it.code < 32 }) {
                        result.error("invalid", "Invalid file.", null)
                    } else {
                        pendingPdf = bytes
                        pendingPdfResult = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (textFile) "text/plain" else if (docxFile) docxMime else if (imageFile) pictureMime!! else "application/pdf"
                                putExtra(Intent.EXTRA_TITLE, filename)
                            }, pdfRequestCode)
                        } catch (_: Exception) {
                            pendingPdf = null
                            pendingPdfResult = null
                            result.error("unavailable", "Unable to open the file picker.", null)
                        }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jiggo/notification_settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                } else result.notImplemented()
            }
    }

    @Deprecated("Uses the document picker result for Android file saving")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == textOpenRequestCode) {
            val result = pendingTextOpen ?: return
            val limit = pendingOpenLimit
            pendingTextOpen = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            Thread {
                try {
                    var name = if (limit == 10 * 1024 * 1024) "document.pdf" else if (limit == 2 * 1024 * 1024) "document.docx" else "document.txt"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                    }
                    val stream = contentResolver.openInputStream(uri) ?: throw IllegalStateException()
                    val output = java.io.ByteArrayOutputStream()
                    stream.use { input ->
                        val buffer = ByteArray(8192)
                        var count = input.read(buffer)
                        while (count != -1) {
                            if (output.size() + count > limit) throw IllegalArgumentException("File too large")
                            output.write(buffer, 0, count)
                            count = input.read(buffer)
                        }
                    }
                    val bytes = output.toByteArray()
                    runOnUiThread { result.success(mapOf("name" to name, "bytes" to bytes)) }
                } catch (_: Exception) {
                    runOnUiThread { result.error("read-failed", "Unable to read this text file.", null) }
                }
            }.start()
            return
        }
        if (requestCode != pdfRequestCode) return
        val result = pendingPdfResult ?: return
        val bytes = pendingPdf
        pendingPdf = null
        pendingPdfResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            result.success(false)
            return
        }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri, "w")
                    ?: throw IllegalStateException("No output stream")
                stream.use { it.write(bytes) }
                runOnUiThread { result.success(true) }
            } catch (_: Exception) {
                runOnUiThread { result.error("write-failed", "Unable to save the file.", null) }
            }
        }.start()
    }
}
