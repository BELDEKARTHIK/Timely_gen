package com.college.timetable_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.w3c.dom.NodeList

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.college.timetable_app/file"
    private val REQUEST_CODE = 9999
    private val TAG = "TimetableApp"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "pickExcelFile") {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "*/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(Intent.createChooser(intent, "Select Excel File"), REQUEST_CODE)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE) return

        val result = pendingResult
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }

        try {
            val uri: Uri = data.data!!
            Log.d(TAG, "Picked: $uri")
            val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            Log.d(TAG, "Read ${bytes.size} bytes")
            val json = parseXlsxToJson(bytes)
            Log.d(TAG, "Parsed OK: ${json.getJSONArray("sheets").length()} sheets")
            result?.success(json.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed: ${e.message}", e)
            result?.error("PARSE_ERROR", e.message, null)
        }
    }

    private fun parseXlsxToJson(bytes: ByteArray): JSONObject {
        val dbf = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = false
        }

        val entries = mutableMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                entries[entry.name] = zis.readBytes()
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
        Log.d(TAG, "Zip entries: ${entries.keys.joinToString()}")

        val sharedStrings = mutableListOf<String>()
        entries["xl/sharedStrings.xml"]?.let { data ->
            val doc = dbf.newDocumentBuilder().parse(ByteArrayInputStream(data))
            val siList: NodeList = doc.getElementsByTagName("si")
            for (i in 0 until siList.length) {
                val si = siList.item(i) as Element
                val tNodes = si.getElementsByTagName("t")
                val sb = StringBuilder()
                for (j in 0 until tNodes.length) {
                    sb.append(tNodes.item(j).textContent)
                }
                sharedStrings.add(sb.toString())
            }
        }
        Log.d(TAG, "Shared strings: ${sharedStrings.size}")

        val rIdToName = mutableMapOf<String, String>()
        entries["xl/workbook.xml"]?.let { data ->
            val doc = dbf.newDocumentBuilder().parse(ByteArrayInputStream(data))
            val sheets = doc.getElementsByTagName("sheet")
            for (i in 0 until sheets.length) {
                val s = sheets.item(i) as Element
                val name = s.getAttribute("name")
                val rId  = s.getAttribute("r:id").ifEmpty { s.getAttribute("id") }
                if (name.isNotEmpty() && rId.isNotEmpty()) rIdToName[rId] = name
            }
        }
        Log.d(TAG, "Sheet names from workbook: $rIdToName")

        val rIdToPath = mutableMapOf<String, String>()
        entries["xl/_rels/workbook.xml.rels"]?.let { data ->
            val doc = dbf.newDocumentBuilder().parse(ByteArrayInputStream(data))
            val rels = doc.getElementsByTagName("Relationship")
            for (i in 0 until rels.length) {
                val r      = rels.item(i) as Element
                val id     = r.getAttribute("Id")
                var target = r.getAttribute("Target")
                if (!target.startsWith("xl/")) target = "xl/$target"
                if (id.isNotEmpty()) rIdToPath[id] = target
            }
        }
        Log.d(TAG, "Rels: $rIdToPath")

        val sheetsJson = JSONArray()
        val orderedRIds = rIdToName.keys.toList()

        for (rId in orderedRIds) {
            val sheetName = rIdToName[rId] ?: continue
            val sheetPath = rIdToPath[rId] ?: continue
            val sheetData = entries[sheetPath] ?: continue

            Log.d(TAG, "Parsing sheet '$sheetName' from $sheetPath")
            val rowsJson = parseSheetXml(sheetData, sharedStrings, dbf)

            val sheetObj = JSONObject()
            sheetObj.put("name", sheetName)
            sheetObj.put("rows", rowsJson)
            sheetsJson.put(sheetObj)
        }

        if (sheetsJson.length() == 0) {
            Log.w(TAG, "Rels empty, trying fallback sheet scan")
            entries.keys
                .filter { it.matches(Regex("xl/worksheets/sheet\\d+\\.xml")) }
                .sorted()
                .forEachIndexed { i, path ->
                    val data = entries[path] ?: return@forEachIndexed
                    val rowsJson = parseSheetXml(data, sharedStrings, dbf)
                    val sheetObj = JSONObject()
                    sheetObj.put("name", "Sheet${i + 1}")
                    sheetObj.put("rows", rowsJson)
                    sheetsJson.put(sheetObj)
                }
        }

        val result = JSONObject()
        result.put("sheets", sheetsJson)
        return result
    }

    private fun parseSheetXml(
        data: ByteArray,
        sharedStrings: List<String>,
        dbf: DocumentBuilderFactory
    ): JSONArray {
        val rowsJson = JSONArray()
        val doc = dbf.newDocumentBuilder().parse(ByteArrayInputStream(data))
        val rowNodes = doc.getElementsByTagName("row")

        for (r in 0 until rowNodes.length) {
            val rowEl  = rowNodes.item(r) as Element
            val cellNodes = rowEl.getElementsByTagName("c")
            val rowArr = JSONArray()
            var lastColIdx = -1

            for (c in 0 until cellNodes.length) {
                val cell   = cellNodes.item(c) as Element
                val ref    = cell.getAttribute("r")
                val type   = cell.getAttribute("t")
                val colIdx = if (ref.isEmpty()) lastColIdx + 1 else colLetterToIndex(ref)

                while (rowArr.length() < colIdx) rowArr.put("")

                val vNodes = cell.getElementsByTagName("v")
                val v = if (vNodes.length > 0) vNodes.item(0).textContent else ""

                val cellValue = when (type) {
                    "s" -> {
                        val idx = v.toIntOrNull() ?: -1
                        if (idx >= 0 && idx < sharedStrings.size) sharedStrings[idx] else ""
                    }
                    "inlineStr" -> {
                        val tNodes = cell.getElementsByTagName("t")
                        (0 until tNodes.length).joinToString("") { tNodes.item(it).textContent }
                    }
                    "b" -> if (v == "1") "TRUE" else "FALSE"
                    else -> v
                }

                rowArr.put(cellValue)
                lastColIdx = colIdx
            }
            rowsJson.put(rowArr)
        }
        return rowsJson
    }

    private fun colLetterToIndex(ref: String): Int {
        var col = 0
        for (ch in ref) {
            if (!ch.isLetter()) break
            col = col * 26 + (ch.uppercaseChar() - 'A' + 1)
        }
        return col - 1
    }
}
