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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@UnstableApi
class PreloadHelper(private val context: Context, private val uri: Uri) {

    fun preCacheVideoBlocking() {
        kotlinx.coroutines.runBlocking {
            preCacheVideo()
        }
    }
    companion object {
        const val TAG = "PreloadHelper"
        const val CACHE_SIZE = 100L * 1024 * 1024 // 100 MB
        private var cacheInstance: SimpleCache? = null
        const val PRE_CACHE_SIZE = 1 * 1024 * 1024L // 1 MB
    }

    private val cache: Cache by lazy {
        cacheInstance ?: run {
            val exoCacheDir = File(context.cacheDir, "exo")
            if (!exoCacheDir.exists()) exoCacheDir.mkdirs()
            val evictor = LeastRecentlyUsedCacheEvictor(CACHE_SIZE)
            SimpleCache(exoCacheDir, evictor, ExoDatabaseProvider(context)).also {
                cacheInstance = it
            }
        }
    }

    private val upstreamDataSourceFactory by lazy {
        DefaultDataSourceFactory(context, "Android")
    }

    private val cacheDataSourceFactory by lazy {
        CacheDataSource.Factory()
            .setCache(cache)
            .setUpstreamDataSourceFactory(upstreamDataSourceFactory)
            .setCacheWriteDataSinkFactory(
                CacheDataSink.Factory().setCache(cache).setFragmentSize(CacheDataSink.DEFAULT_FRAGMENT_SIZE)
            )
            .setEventListener(object : CacheDataSource.EventListener {
                override fun onCachedBytesRead(cacheSizeBytes: Long, cachedBytesRead: Long) {
                    Log.d(TAG, "onCachedBytesRead. cacheSizeBytes:$cacheSizeBytes, cachedBytesRead: $cachedBytesRead")
                }

                override fun onCacheIgnored(reason: Int) {
                    Log.d(TAG, "onCacheIgnored. reason:$reason")
                }
            })
    }

    private val player by lazy {
        ExoPlayer.Builder(context)
            .build().apply {
                repeatMode = Player.REPEAT_MODE_OFF
                playWhenReady = true
                addListener(object : Player.Listener {
                    override fun onPlayerStateChanged(playWhenReady: Boolean, playbackState: Int) {
                        super.onPlayerStateChanged(playWhenReady, playbackState)
                        Log.d(
                            TAG,
                            "onPlayerStateChanged. playWhenReady: $playWhenReady, playbackState: $playbackState)"
                        )
                    }
                })
            }
    }


    private val cacheStreamKeys = arrayListOf(
        StreamKey(0, 1),
        StreamKey(1, 1),
        StreamKey(2, 1),
        StreamKey(3, 1),
        StreamKey(4, 1)
    )

    private val downloader by lazy {
        HlsDownloader(
            MediaItem.Builder()
                .setUri(uri)
                .setStreamKeys(cacheStreamKeys)
                .build(),
            cacheDataSourceFactory
        )
    }

    private fun cancelPreCache() {
        downloader.cancel()
    }

    private suspend fun preCacheVideo() = withContext(Dispatchers.IO) {
        runCatching {
            // Check if enough data is already cached
            if (cache.isCached(uri.toString(), 0, PRE_CACHE_SIZE)) {
                Log.d(TAG, "Video has been cached. Skipping download.")
                return@runCatching
            }

            downloader.download { contentLength, bytesDownloaded, percentDownloaded ->
                if (bytesDownloaded >= PRE_CACHE_SIZE) downloader.cancel()
                Log.d(
                    TAG,
                    "ContentLength: $contentLength, BytesDownloaded: $bytesDownloaded, PercentDownloaded: $percentDownloaded"
                )
            }
        }.onFailure {
            if (it is InterruptedException) return@onFailure
            Log.e(TAG, "Video cache failed: ${it.message}", it)
        }
    }
}
