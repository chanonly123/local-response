package com.chanonly123.androidtestapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.chanonly123.androidtestapp.catalog.ApiCatalog
import com.chanonly123.androidtestapp.catalog.ApiGroup
import com.chanonly123.androidtestapp.catalog.ApiSample
import com.chanonly123.androidtestapp.catalog.CallOutcome
import com.chanonly123.androidtestapp.ui.theme.AndroidTestAppTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroidTestAppTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    CatalogScreen(modifier = Modifier.padding(innerPadding))
                }
            }
        }
    }
}

/// What a sample is doing, keyed by title. Held here rather than inside each
/// row so a row scrolled out of view and back keeps its last result.
private class SampleState {
    val running = mutableStateMapOf<String, Boolean>()
    val outcomes = mutableStateMapOf<String, CallOutcome>()
}

@Composable
fun CatalogScreen(modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val state = remember { SampleState() }
    val expanded = remember { mutableStateMapOf<String, Boolean>() }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Column(modifier = Modifier.padding(bottom = 8.dp)) {
                Text("Local Response test app", style = MaterialTheme.typography.headlineSmall)
                Text(
                    "Every call goes through the interceptor — watch them land in the mapper.",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }

        ApiCatalog.groups.forEach { group ->
            item(key = group.name) {
                GroupHeader(
                    group = group,
                    expanded = expanded[group.name] ?: false,
                    onToggle = { expanded[group.name] = !(expanded[group.name] ?: false) }
                )
            }

            if (expanded[group.name] == true) {
                items(group.samples, key = { "${group.name}/${it.title}" }) { sample ->
                    SampleRow(
                        sample = sample,
                        isRunning = state.running[sample.title] == true,
                        outcome = state.outcomes[sample.title],
                        onRun = {
                            if (state.running[sample.title] == true) return@SampleRow
                            state.running[sample.title] = true
                            scope.launch {
                                val result = try {
                                    sample.run()
                                } catch (e: Exception) {
                                    CallOutcome.failure("${e.javaClass.simpleName}: ${e.message}")
                                }
                                state.outcomes[sample.title] = result
                                state.running[sample.title] = false
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun GroupHeader(group: ApiGroup, expanded: Boolean, onToggle: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth().clickable { onToggle() }
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = group.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = "${group.samples.size}  ${if (expanded) "−" else "+"}",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSecondaryContainer
            )
        }
    }
}

@Composable
private fun SampleRow(
    sample: ApiSample,
    isRunning: Boolean,
    outcome: CallOutcome?,
    onRun: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(enabled = !isRunning) { onRun() },
        colors = CardDefaults.cardColors(
            containerColor = when {
                outcome == null -> MaterialTheme.colorScheme.surfaceVariant
                outcome.ok -> MaterialTheme.colorScheme.surfaceVariant
                else -> MaterialTheme.colorScheme.errorContainer
            }
        )
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(sample.title, style = MaterialTheme.typography.titleSmall)
                    Text(
                        sample.subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace
                    )
                }
                if (isRunning) {
                    Spacer(Modifier.width(8.dp))
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                }
            }

            AnimatedVisibility(visible = outcome != null) {
                outcome?.let {
                    Text(
                        text = it.text,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
        }
    }
}
