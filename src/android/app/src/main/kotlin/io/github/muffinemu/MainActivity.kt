// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

package io.github.muffinemu

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** The library: the games in Roms, an Add game button, and a keys.txt importer. */
class MainActivity : ComponentActivity() {
    private val cream = Color(0xFFF4E9DC)
    private val ground = Color(0xFF17110C)
    private val accent = Color(0xFFF0A35E)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = accent, background = ground, surface = Color(0xFF221A13))) {
                Library()
            }
        }
    }

    @Composable
    private fun Library() {
        val games = remember { mutableStateListOf<File>() }
        var coreReady by remember { mutableStateOf(false) }
        var status by remember { mutableStateOf("Starting the emulator core…") }
        var keyCount by remember { mutableStateOf(-1) }
        // What is being copied in, or the last copy's error. A disc image runs to tens of gigabytes, so the copy
        // runs off the main thread and the list waits for it.
        var copyStatus by remember { mutableStateOf<String?>(null) }
        val scope = rememberCoroutineScope()

        fun copyIn(uri: Uri, dir: File, fixedName: String? = null, then: () -> Unit) {
            val name = fixedName ?: queryDisplayName(uri) ?: "game"
            copyStatus = "Copying $name…"
            scope.launch {
                val error = withContext(Dispatchers.IO) { runCatching { importInto(uri, dir, name) }.exceptionOrNull() }
                copyStatus = error?.let { "Couldn't copy $name: ${it.message ?: it.javaClass.simpleName}" }
                then()
            }
        }

        fun rescan() {
            games.clear()
            games.addAll(listGames(MuffinApp.romsDir(this)))
        }

        LaunchedEffect(Unit) {
            rescan()
            val ok = withContext(Dispatchers.IO) { MuffinApp.startCore(this@MainActivity) }
            coreReady = ok
            status = NativeBridge.statusText()
            if (ok) keyCount = NativeBridge.reloadAndCountKeys()
        }

        val addGame = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) copyIn(uri, MuffinApp.romsDir(this)) { rescan() }
        }
        val addKeys = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) copyIn(uri, MuffinApp.mlcDir(this), fixedName = "keys.txt") {
                if (coreReady) keyCount = NativeBridge.reloadAndCountKeys()
            }
        }

        Column(
            modifier = Modifier.fillMaxSize().background(ground).safeDrawingPadding().padding(20.dp)
        ) {
            Text("MuffinEMU", color = cream, fontSize = 28.sp)
            Text(
                if (coreReady) "Core ready. Keys loaded: ${if (keyCount < 0) "none" else keyCount}" else status,
                color = cream.copy(alpha = 0.7f), fontSize = 13.sp
            )
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = { addGame.launch(arrayOf("*/*")) }, enabled = copyStatus?.startsWith("Copying") != true) { Text("Add game") }
                OutlinedButton(onClick = { addKeys.launch(arrayOf("*/*")) }, enabled = copyStatus?.startsWith("Copying") != true) { Text("Add keys.txt") }
            }
            copyStatus?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = cream.copy(alpha = 0.8f), fontSize = 13.sp)
            }
            Spacer(Modifier.height(16.dp))
            if (games.isEmpty()) {
                Text(
                    "No games yet. Add a game file (.wua, .wud, .wux, .iso, .rpx), or put games in\n" +
                        "Android/data/io.github.muffinemu/files/Roms with a file manager.",
                    color = cream.copy(alpha = 0.8f), fontSize = 14.sp
                )
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(games, key = { it.absolutePath }) { game ->
                    Text(
                        game.nameWithoutExtension,
                        color = ground,
                        fontSize = 17.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(cream, RoundedCornerShape(14.dp))
                            .clickable(enabled = coreReady) {
                                startActivity(Intent(this@MainActivity, GameActivity::class.java).putExtra(GameActivity.EXTRA_PATH, game.absolutePath))
                            }
                            .padding(16.dp)
                    )
                }
            }
        }
    }

    private fun listGames(dir: File): List<File> {
        val extensions = setOf("wua", "wud", "wux", "iso", "rpx")
        val files = dir.listFiles() ?: return emptyList()
        return files.filter { f ->
            f.isFile && f.extension.lowercase() in extensions ||
                // an extracted game folder: code/, content/, meta/
                f.isDirectory && File(f, "code").isDirectory && File(f, "content").isDirectory
        }.sortedBy { it.name.lowercase() }
    }

    /**
     * Copies a picked document into MuffinEMU's own folder; the original is left where it is. Blocking. The copy
     * goes to name.part and is renamed at the end, so a copy cut short never shows up in the library as a game.
     */
    private fun importInto(uri: Uri, dir: File, name: String) {
        val target = File(dir, name)
        val partial = File(dir, "$name.part")
        try {
            val input = contentResolver.openInputStream(uri) ?: error("the file couldn't be opened")
            input.use { src -> partial.outputStream().use { src.copyTo(it, bufferSize = 1 shl 20) } }
            target.delete()
            if (!partial.renameTo(target)) error("the copy couldn't be put in place")
        } finally {
            partial.delete()
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) return c.getString(0)
        }
        return null
    }
}
