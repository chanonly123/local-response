package com.chanonly123.androidtestapp

import okhttp3.ResponseBody
import retrofit2.Response

class PostRepository(private val apiService: JsonPlaceholderService) {

    suspend fun getPost(id: Int): Response<ResponseBody> {
        return apiService.getPost(id)
    }

    suspend fun createPost(post: Post): Response<ResponseBody> {
        return apiService.createPost(post)
    }
}