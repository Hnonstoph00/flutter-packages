// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static androidx.media3.common.Player.REPEAT_MODE_ALL;
import static androidx.media3.common.Player.REPEAT_MODE_OFF;

import android.content.Context;
import android.net.Uri;
import android.util.Log;
import android.view.Surface;

import androidx.annotation.OptIn;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RestrictTo;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.cache.Cache;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.source.MediaSource;

import io.flutter.view.TextureRegistry;

final class VideoPlayer implements TextureRegistry.SurfaceProducer.Callback {
  @NonNull private final Context context;
  @NonNull private final ExoPlayerProvider exoPlayerProvider;
  @NonNull private final MediaItem mediaItem;
  @NonNull private final TextureRegistry.SurfaceProducer surfaceProducer;
  @NonNull private final VideoPlayerCallbacks videoPlayerEvents;
  @NonNull private final VideoPlayerOptions options;
  @NonNull private ExoPlayer exoPlayer;
  @Nullable private ExoPlayerState savedStateDuring;

  /**
   * Creates a video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param surfaceProducer produces a texture to render to.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  @OptIn(markerClass = UnstableApi.class)
  @NonNull
  static VideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new VideoPlayer(context,
        () -> {
          ExoPlayer.Builder builder;
          if (options.useCache) {

              builder = new ExoPlayer.Builder(context);

          } else {
              builder = new ExoPlayer.Builder(context).setMediaSourceFactory(asset.getMediaSourceFactory(context));
          }
          DefaultLoadControl.Builder loadBuilder = new DefaultLoadControl.Builder();
          loadBuilder.setBufferDurationsMs(
                  options.minBufferMs,
                  options.maxBufferMs,
                  options.bufferForPlaybackMs,
                  options.bufferForPlaybackAfterRebufferMs
          );
          DefaultLoadControl loadControl = loadBuilder.build();
          builder.setLoadControl(loadControl);

          return builder.build();
        },
        events,
        surfaceProducer,
        asset.getMediaItem(),
        options);
  }
  /**
   * Precache a video player.
   *
   * @param context application context.
   * @param asset   asset to play.
   * @param options options for playback.
   */
  @OptIn(markerClass = UnstableApi.class)
  static boolean preCache(
          Context context,
          VideoAsset asset,
          VideoPlayerOptions options, Uri uri) {
      if (options.useCache) {
        PreloadHelper preloadHelper = new PreloadHelper(context,uri);
        preloadHelper.preCacheVideoBlocking();

        return true;
      }
      return false;
  }

  /** A closure-compatible signature since {@link java.util.function.Supplier} is API level 24. */
  interface ExoPlayerProvider {
    /**
     * Returns a new {@link ExoPlayer}.
     *
     * @return new instance.
     */
    ExoPlayer get();
  }

  @VisibleForTesting
  VideoPlayer(
          @NonNull Context context,
      @NonNull ExoPlayerProvider exoPlayerProvider,
      @NonNull VideoPlayerCallbacks events,
      @NonNull TextureRegistry.SurfaceProducer surfaceProducer,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options
      ) {
    this.context = context;
    this.exoPlayerProvider = exoPlayerProvider;
    this.videoPlayerEvents = events;
    this.surfaceProducer = surfaceProducer;
    this.mediaItem = mediaItem;
    this.options = options;
    this.exoPlayer = createVideoPlayer();
    surfaceProducer.setCallback(this);
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  // TODO(matanlurey): https://github.com/flutter/flutter/issues/155131.
  @SuppressWarnings({"deprecation", "removal"})
  public void onSurfaceCreated() {
    if (savedStateDuring != null) {
      exoPlayer = createVideoPlayer();
      savedStateDuring.restore(exoPlayer);
      savedStateDuring = null;
    }
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceDestroyed() {
    // Intentionally do not call pause/stop here, because the surface has already been released
    // at this point (see https://github.com/flutter/flutter/issues/156451).
    savedStateDuring = ExoPlayerState.save(exoPlayer);
    exoPlayer.release();
  }

    @OptIn(markerClass = UnstableApi.class)
    private ExoPlayer createVideoPlayer() {
    ExoPlayer exoPlayer = exoPlayerProvider.get();
    exoPlayer.setPlayWhenReady(false);
    Cache cache = CacheManager.INSTANCE.getCache(context);

    CacheDataSource.Factory dataSourceFactory = CacheDataSourceFactoryManager.Companion.getInstance(context, cache);
    MediaSource mediaSource = new HlsMediaSource.Factory(dataSourceFactory)
            .setAllowChunklessPreparation(true)
            .createMediaSource(mediaItem);


    exoPlayer.setMediaSource(mediaSource);

    exoPlayer.prepare();

    exoPlayer.setVideoSurface(surfaceProducer.getSurface());

    boolean wasInitialized = savedStateDuring != null;
    exoPlayer.addListener(new ExoPlayerEventListener(exoPlayer, videoPlayerEvents, wasInitialized));
    setAudioAttributes(exoPlayer, options.mixWithOthers);

    return exoPlayer;
  }

  void sendBufferingUpdate() {
    videoPlayerEvents.onBufferingUpdate(exoPlayer.getBufferedPosition());
  }

  private static void setAudioAttributes(ExoPlayer exoPlayer, boolean isMixMode) {
    exoPlayer.setAudioAttributes(
        new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
        !isMixMode);
  }

  void play() {
    exoPlayer.play();
  }

  void pause() {
    exoPlayer.pause();
  }

  void setLooping(boolean value) {
    exoPlayer.setRepeatMode(value ? REPEAT_MODE_ALL : REPEAT_MODE_OFF);
  }

  void setVolume(double value) {
    float bracketedValue = (float) Math.max(0.0, Math.min(1.0, value));
    exoPlayer.setVolume(bracketedValue);
  }

  void setPlaybackSpeed(double value) {
    // We do not need to consider pitch and skipSilence for now as we do not handle them and
    // therefore never diverge from the default values.
    final PlaybackParameters playbackParameters = new PlaybackParameters(((float) value));

    exoPlayer.setPlaybackParameters(playbackParameters);
  }

  void seekTo(int location) {
    exoPlayer.seekTo(location);
  }

  long getPosition() {
    return exoPlayer.getCurrentPosition();
  }

  void dispose() {
    exoPlayer.release();
    surfaceProducer.release();

    // TODO(matanlurey): Remove when embedder no longer calls-back once released.
    // https://github.com/flutter/flutter/issues/156434.
    surfaceProducer.setCallback(null);
  }
}
