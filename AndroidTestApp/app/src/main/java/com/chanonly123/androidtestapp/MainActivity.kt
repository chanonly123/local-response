package com.chanonly123.androidtestapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.chanonly123.androidtestapp.Post
import com.chanonly123.androidtestapp.NetworkModule
import com.chanonly123.androidtestapp.PostRepository
import com.chanonly123.androidtestapp.ui.theme.AndroidTestAppTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val repository = PostRepository(NetworkModule.apiService)
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroidTestAppTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    RequestTestScreen(
                        repository = repository,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}

@Composable
fun RequestTestScreen(repository: PostRepository, modifier: Modifier = Modifier) {
    var getResponse by remember { mutableStateOf("No GET request made yet") }
    var postResponse by remember { mutableStateOf("No POST request made yet") }
    var isLoading by remember { mutableStateOf(false) }
    
    val coroutineScope = rememberCoroutineScope()
    
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Retrofit Request Test App",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(bottom = 16.dp)
        )
        
        // GET Request Button
        Button(
            onClick = {
                coroutineScope.launch {
                    isLoading = true
                    getResponse = makeGetRequest(repository)
                    isLoading = false
                }
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isLoading
        ) {
            Text("Make GET Request")
        }
        
        // GET Response Card
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = "GET Response:",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(8.dp)
            )
            Text(
                text = getResponse,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.padding(8.dp)
            )
        }
        
        // POST Request Button
        Button(
            onClick = {
                coroutineScope.launch {
                    isLoading = true
                    postResponse = makePostRequest(repository)
                    isLoading = false
                }
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isLoading
        ) {
            Text("Make POST Request")
        }
        
        // POST Response Card
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = "POST Response:",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(8.dp)
            )
            Text(
                text = postResponse,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.padding(8.dp)
            )
        }
        
        if (isLoading) {
            Text("Loading...", style = MaterialTheme.typography.bodyMedium)
        }
    }
}

suspend fun makeGetRequest(repository: PostRepository): String {
    return withContext(Dispatchers.IO) {
        try {
            val response = repository.getPost(1)
            
            if (response.isSuccessful) {
                response.body()?.string() ?: ""
            } else {
                "Error: ${response.code()} - ${response.message()}"
            }
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }
}

suspend fun makePostRequest(repository: PostRepository): String {
    return withContext(Dispatchers.IO) {
        try {
            val newPost = Post(
                title = "Test Post",
                body = "This is a test post from Android using Retrofit",
                userId = 1
            )
            
            val response = repository.createPost(newPost)
            
            if (response.isSuccessful) {
                response.body()?.string() ?: "empty"
            } else {
                "Error: ${response.code()} - ${response.message()}"
            }
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello $name!",
        modifier = modifier
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    AndroidTestAppTheme {
        RequestTestScreen(repository = PostRepository(NetworkModule.apiService))
    }
}