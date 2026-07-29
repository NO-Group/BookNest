#!/usr/bin/env kotlin

package com.n.o_group.tether.app.data.supabase

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.storage.Storage

object SupabaseClient {

    private const val SUPABASE_URL = "https://evxslesfixnkfgspbsvc.supabase.co"
    private const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV2eHNsZXNmaXhua2Znc3Bic3ZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2MDg0MjUsImV4cCI6MjA5MjE4NDQyNX0.MweBzgqEENRnjYGvn9Hb9p85AmF9vwMvMNmjzc6pw2Y"

    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_ANON_KEY
        ) {
            install(Auth)
            install(Postgrest)
            install(Realtime)
            install(Storage)
        }
    }
}