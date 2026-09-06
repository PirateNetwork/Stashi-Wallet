package com.pirate.wallet

import android.app.Application
import android.content.Context
import com.pirate.wallet.background.SyncWorker

class StashiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (!SyncWorker.BACKGROUND_SYNC_ENABLED) {
            SyncWorker.cancelAllSync(this)
        }
    }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        NativeRuntimeEnvironment.configure(this)
    }
}
