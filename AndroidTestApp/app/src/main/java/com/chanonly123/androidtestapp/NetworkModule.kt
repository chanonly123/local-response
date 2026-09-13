package com.chanonly123.androidtestapp

import com.chanonly123.local_response.LocalResponseConfig
import com.chanonly123.local_response.LocalResponseInterceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

object NetworkModule {

    private const val BASE_URL = "https://jsonplaceholder.typicode.com"

    val logging = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BODY
    }

    /// Exposed so the sample catalogue can make raw OkHttp calls through the
    /// same client — every sample has to pass through LocalResponseInterceptor
    /// or it is not testing anything.
    val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .addInterceptor(interceptor = LocalResponseInterceptor(
                // config = LocalResponseConfig.emulator(),
                config = LocalResponseConfig.localIpAddress(url = "http://192.168.31.86:4040"),
            ))
            .addInterceptor(interceptor = logging)
            .build()
    }

    private val retrofit: Retrofit by lazy {
        Retrofit.Builder()
            .baseUrl(BASE_URL)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    val apiService: JsonPlaceholderService by lazy {
        retrofit.create(JsonPlaceholderService::class.java)
    }
}