package com.example.nexus_video

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nexus/media_packager",
        ).setMethodCallHandler { call, result ->
            if (call.method != "mux") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val videoPath = call.argument<String>("videoPath")
            val audioPath = call.argument<String>("audioPath")
            val outputPath = call.argument<String>("outputPath")
            val dropAudio = call.argument<Boolean>("dropAudio") ?: false
            if (outputPath.isNullOrEmpty() ||
                (videoPath.isNullOrEmpty() && audioPath.isNullOrEmpty())
            ) {
                result.error("bad_arguments", "缺少输入或输出路径", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    mux(videoPath, audioPath, dropAudio, outputPath)
                    runOnUiThread { result.success(null) }
                } catch (error: Exception) {
                    Log.e("NexusMuxer", "media mux failed", error)
                    File(outputPath).delete()
                    runOnUiThread {
                        result.error(
                            "mux_failed",
                            error.message ?: "媒体合并失败",
                            null,
                        )
                    }
                }
            }.start()
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nexus/platform",
        ).setMethodCallHandler { call, result ->
            if (call.method == "copyFolderToDownloads") {
                val path = call.argument<String>("path")?.trim()
                if (path.isNullOrEmpty()) {
                    result.error("bad_arguments", "缺少目录路径", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val count = copyFolderToDownloads(path)
                        runOnUiThread { result.success(count) }
                    } catch (error: Exception) {
                        Log.e("NexusExport", "copy folder failed", error)
                        runOnUiThread {
                            result.error(
                                "copy_failed",
                                error.message ?: "复制目录失败",
                                null,
                            )
                        }
                    }
                }.start()
                return@setMethodCallHandler
            }
            try {
                val opened = when (call.method) {
                    "openFile" -> {
                        val path = call.argument<String>("path")?.trim()
                        if (path.isNullOrEmpty()) false else openFile(path)
                    }
                    "openFolder" -> {
                        val path = call.argument<String>("path")?.trim()
                        if (path.isNullOrEmpty()) false else openFolder(path)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")?.trim()
                        if (url.isNullOrEmpty()) false else openUrl(url)
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(opened)
            } catch (error: Exception) {
                Log.e("NexusPlatform", "open failed", error)
                result.error("open_failed", error.message ?: "无法打开", null)
            }
        }
    }

    private fun copyFolderToDownloads(path: String): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("复制到下载目录需要 Android 10 或更高版本")
        }
        val source = File(path)
        val sourceDir = when {
            source.isDirectory -> source
            source.isFile -> source.parentFile
            else -> null
        } ?: throw IllegalArgumentException("目录不存在：$path")
        val folderName = sourceDir.name.ifEmpty { "Nexus" }
        val files = sourceDir.walkTopDown()
            .filter { it.isFile }
            .filter { file ->
                val relative = file.relativeTo(sourceDir).invariantSeparatorsPath
                relative.split('/').none { it.startsWith(".") }
            }
            .toList()
        if (files.isEmpty()) {
            return 0
        }
        var copied = 0
        val resolver = contentResolver
        for (file in files) {
            val relative = file.relativeTo(sourceDir).invariantSeparatorsPath
            val relativeParent = relative.substringBeforeLast('/', "")
            val relativePath = buildString {
                append(Environment.DIRECTORY_DOWNLOADS)
                append("/Nexus/")
                if (folderName != "Nexus") {
                    append(folderName)
                    append("/")
                }
                if (relativeParent.isNotEmpty()) {
                    append(relativeParent)
                    append("/")
                }
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                put(MediaStore.MediaColumns.MIME_TYPE, fileMimeType(file.path))
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IOException("无法创建下载文件：${file.name}")
            try {
                val output = resolver.openOutputStream(uri)
                    ?: throw IOException("无法写入下载文件：${file.name}")
                output.use {
                    file.inputStream().use { input -> input.copyTo(it) }
                }
                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, done, null, null)
                copied += 1
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }
        return copied
    }

    private fun openFile(path: String): Boolean {
        val file = File(path)
        if (!file.isFile) {
            return false
        }
        val uri = FileProvider.getUriForFile(
            this,
            "${packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, fileMimeType(path))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun fileMimeType(path: String): String {
        val extension = path.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension) ?: "*/*"
    }

    private fun openFolder(path: String): Boolean {
        val directory = File(path)
        if (!directory.isDirectory) {
            return false
        }
        val externalRoot = Environment.getExternalStorageDirectory().absolutePath
        if (path.startsWith("$externalRoot${File.separator}")) {
            val relative = path.removePrefix("$externalRoot${File.separator}")
            val documentId = "primary:$relative"
            try {
                val uri = DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents",
                    documentId,
                )
                startActivity(
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(
                            uri,
                            DocumentsContract.Document.MIME_TYPE_DIR,
                        )
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    },
                )
                return true
            } catch (_: Exception) {
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val treeUri = DocumentsContract.buildTreeDocumentUri(
                        "com.android.externalstorage.documents",
                        documentId,
                    )
                    startActivity(
                        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            putExtra(DocumentsContract.EXTRA_INITIAL_URI, treeUri)
                        },
                    )
                    return true
                } catch (_: Exception) {
                }
            }
        }
        return try {
            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                directory,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(
                        uri,
                        DocumentsContract.Document.MIME_TYPE_DIR,
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openUrl(url: String): Boolean {
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun mux(
        videoPath: String?,
        audioPath: String?,
        dropAudio: Boolean,
        outputPath: String,
    ) {
        val output = File(outputPath)
        output.parentFile?.mkdirs()
        output.delete()

        val videoExtractor = videoPath?.let { path ->
            MediaExtractor().apply { setDataSource(path) }
        }
        var audioExtractor: MediaExtractor? = null
        try {
            val videoTrack = videoExtractor?.let { findTrack(it, "video/") }
            val audioSource = when {
                audioPath != null -> audioPath
                dropAudio -> null
                else -> videoPath
            }
            if (audioSource != null) {
                audioExtractor = MediaExtractor().apply {
                    setDataSource(audioSource)
                }
            }
            val audioTrack = audioExtractor?.let { findTrack(it, "audio/") }

            if (videoTrack == null && audioTrack == null) {
                throw IllegalArgumentException("输入文件没有可用的音视频轨道")
            }
            if (videoPath != null && videoTrack == null && audioPath == null) {
                throw IllegalArgumentException("视频文件中没有视频轨道")
            }
            if (audioPath != null && audioTrack == null) {
                throw IllegalArgumentException("音频文件中没有音频轨道")
            }

            val muxer = MediaMuxer(
                outputPath,
                MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4,
            )
            var started = false
            try {
                var videoMuxTrack = -1
                var audioMuxTrack = -1
                if (videoTrack != null) {
                    videoExtractor!!.selectTrack(videoTrack)
                    videoMuxTrack = muxer.addTrack(
                        videoExtractor.getTrackFormat(videoTrack),
                    )
                }
                if (audioTrack != null) {
                    audioExtractor!!.selectTrack(audioTrack)
                    audioMuxTrack = muxer.addTrack(
                        audioExtractor.getTrackFormat(audioTrack),
                    )
                }
                muxer.start()
                started = true
                copySamples(
                    videoExtractor,
                    videoMuxTrack,
                    audioExtractor,
                    audioMuxTrack,
                    muxer,
                )
            } finally {
                if (started) {
                    try {
                        muxer.stop()
                    } catch (_: Exception) {
                    }
                }
                muxer.release()
            }
        } finally {
            videoExtractor?.release()
            audioExtractor?.release()
        }
    }

    private fun findTrack(extractor: MediaExtractor, prefix: String): Int? {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(
                MediaFormat.KEY_MIME,
            ) ?: continue
            if (mime.startsWith(prefix)) {
                return index
            }
        }
        return null
    }

    private fun copySamples(
        videoExtractor: MediaExtractor?,
        videoTrack: Int,
        audioExtractor: MediaExtractor?,
        audioTrack: Int,
        muxer: MediaMuxer,
    ) {
        val videoBuffer = ByteBuffer.allocateDirect(16 * 1024 * 1024)
        val audioBuffer = ByteBuffer.allocateDirect(4 * 1024 * 1024)
        val videoInfo = MediaCodec.BufferInfo()
        val audioInfo = MediaCodec.BufferInfo()
        var videoTime = if (videoExtractor != null && videoTrack >= 0) {
            videoExtractor.sampleTime
        } else {
            -1L
        }
        var audioTime = if (audioExtractor != null && audioTrack >= 0) {
            audioExtractor.sampleTime
        } else {
            -1L
        }
        while (videoTime >= 0 || audioTime >= 0) {
            val takeVideo = videoTime >= 0 &&
                (audioTime < 0 || videoTime <= audioTime)
            if (takeVideo) {
                writeSample(
                    videoExtractor!!,
                    videoBuffer,
                    videoInfo,
                    muxer,
                    videoTrack,
                )
                videoTime = videoExtractor.sampleTime
            } else {
                writeSample(
                    audioExtractor!!,
                    audioBuffer,
                    audioInfo,
                    muxer,
                    audioTrack,
                )
                audioTime = audioExtractor.sampleTime
            }
        }
    }

    private fun writeSample(
        extractor: MediaExtractor,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        muxer: MediaMuxer,
        track: Int,
    ) {
        buffer.clear()
        val size = extractor.readSampleData(buffer, 0)
        if (size <= 0) {
            extractor.advance()
            return
        }
        info.offset = 0
        info.size = size
        info.presentationTimeUs = extractor.sampleTime
        info.flags = extractor.sampleFlags
        muxer.writeSampleData(track, buffer, info)
        extractor.advance()
    }
}
