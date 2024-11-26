package io.flutter.plugins.videoplayer

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.StreamKey
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.ExoDatabaseProvider
import androidx.media3.datasource.DefaultDataSourceFactory
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.offline.HlsDownloader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@UnstableApi
class PreloadHelper(private val context: Context, private val uri: Uri) {

    private val cache: Cache by lazy {
        CacheManager.getCache(context)
    }

    private val cacheDataSourceFactory by lazy {
        CacheDataSourceFactoryManager.getInstance(context, cache)
    }

    private val downloader by lazy {
        HlsDownloader(
            MediaItem.Builder()
                .setUri(uri)
                .build(),
            cacheDataSourceFactory
        )
    }

    fun preCacheVideoBlocking() {
        CoroutineScope(Dispatchers.Main).launch {
            preCacheVideo()
        }
    }

    private fun cancelPreCache() {
        downloader.cancel()
    }

    private suspend fun preCacheVideo() = withContext(Dispatchers.IO) {
        runCatching {
            if (cache.isCached(uri.toString(), 0, PRE_CACHE_SIZE)) {
                Log.d(TAG, "Video has been cached. Skipping download.")
                return@runCatching
            }

            downloader.download { contentLength, bytesDownloaded, percentDownloaded ->
                if (bytesDownloaded >= PRE_CACHE_SIZE) cancelPreCache()
                Log.d(TAG, " uri: $uri ContentLength: $contentLength, BytesDownloaded: $bytesDownloaded, PercentDownloaded: $percentDownloaded")
            }
        }.onFailure {
            if (it is InterruptedException) return@onFailure
            Log.e(TAG, "Video cache failed: ${it.message}", it)
        }
    }

    companion object {
        private const val TAG = "CacheDataSource"
        private const val PRE_CACHE_SIZE = 1 * 512 * 1024L // 1 MB
    }
}



@UnstableApi
object CacheManager {
    private const val TAG = "CacheManager"
    const val CACHE_SIZE = 100L * 1024 * 1024 // 100 MB
    private var cacheInstance: SimpleCache? = null

    fun getCache(context: Context): Cache {
        if (cacheInstance == null) {
            synchronized(this) {
                if (cacheInstance == null) {
                    val exoCacheDir = File(context.cacheDir, "exo")
                    if (!exoCacheDir.exists()) exoCacheDir.mkdirs()
                    val evictor = LeastRecentlyUsedCacheEvictor(CACHE_SIZE)
                    cacheInstance = SimpleCache(exoCacheDir, evictor, ExoDatabaseProvider(context))
                }
            }
        }
        return cacheInstance!!
    }
}

@UnstableApi
class CacheDataSourceFactoryManager(private val context: Context) {
    private val upstreamDataSourceFactory: DefaultDataSourceFactory by lazy {
        DefaultDataSourceFactory(context, "Android")
    }

    companion object {
        private var cacheDataSourceFactory: CacheDataSource.Factory? = null

        fun getInstance(context: Context, cache: Cache): CacheDataSource.Factory {
            if (cacheDataSourceFactory == null) {
                cacheDataSourceFactory = CacheDataSource.Factory()
                    .setCache(cache)
                    .setUpstreamDataSourceFactory(DefaultDataSourceFactory(context, "Android"))
                    .setCacheWriteDataSinkFactory(
                        CacheDataSink.Factory()
                            .setCache(cache)
                            .setFragmentSize(CacheDataSink.DEFAULT_FRAGMENT_SIZE)
                    )
                    .setEventListener(object : CacheDataSource.EventListener {
                        override fun onCachedBytesRead(cacheSizeBytes: Long, cachedBytesRead: Long) {
                            Log.d("CacheDataSource", "onCachedBytesRead: cacheSizeBytes=$cacheSizeBytes, cachedBytesRead=$cachedBytesRead")
                        }

                        override fun onCacheIgnored(reason: Int) {
                            Log.d("CacheDataSource", "onCacheIgnored: reason=$reason")
                        }
                    })
            }
            return cacheDataSourceFactory!!
        }
    }
}

