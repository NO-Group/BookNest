#!/usr/bin/env kotlin

package com.n.o_group.tether.app.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class User(
    val id: String,
    val username: String,
    @SerialName("display_name")
    val displayName: String? = null,
    @SerialName("phone_number")
    val phoneNumber: String? = null,
    @SerialName("avatar_url")
    val avatarUrl: String? = null,
    val bio: String = "",
    @SerialName("favorite_genres")
    val favoriteGenres: List<String> = emptyList(),
    val status: String = "offline",
    val gems: Int = 77,
    @SerialName("total_gems_purchased")
    val totalGemsPurchased: Int = 0,
    @SerialName("total_gems_spent")
    val totalGemsSpent: Int = 0,
    @SerialName("last_seen")
    val lastSeen: String? = null,
    @SerialName("created_at")
    val createdAt: String? = null
)