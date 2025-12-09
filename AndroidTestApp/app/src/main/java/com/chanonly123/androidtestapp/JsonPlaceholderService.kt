package com.chanonly123.androidtestapp

import okhttp3.Call
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Headers
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Url


interface JsonPlaceholderService {

    @Headers("abc: xyz")
    @GET("/posts/{id}?pqr=cde")
    suspend fun getPost(@Path("id") id: Int): Response<ResponseBody>

    @POST("/posts")
    suspend fun createPost(@Body post: Post): Response<ResponseBody>

    @GET
    fun testError(@Url url: String?): Response<ResponseBody>
}