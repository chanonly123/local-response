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

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .addInterceptor(interceptor = LocalResponseInterceptor(config = LocalResponseConfig.emulator()))
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