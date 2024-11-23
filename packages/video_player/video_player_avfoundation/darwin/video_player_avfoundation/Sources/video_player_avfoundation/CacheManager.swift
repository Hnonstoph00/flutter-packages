// import AVKit
// import Cache
// import GCDWebServer
// import HLSCachingReverseProxyServer
// import PINCache
//
//  class CacheManager: NSObject {
//    var diskCacheSize: UInt = 1024 * 1024 * 1024
//
//    // We store the last pre-cached CachingPlayerItem objects to be able to play even if the download
//    // has not finished.
//    var _preCachedURLs = [String: CachingPlayerItem]()
//
//    var completionHandler: ((_ success: Bool) -> Void)? = nil
//
//    lazy var diskConfig = DiskConfig(name: "VideoPlayerCache", expiry: .date(Date().addingTimeInterval(3600 * 24 * 30)),
//                                     maxSize: diskCacheSize)
//
//    // Flag whether the CachingPlayerItem was already cached.
//    var _existsInStorage: Bool = false
//
//    let memoryConfig = MemoryConfig(
//        // Expiry date that will be applied by default for every added object
//        // if it's not overridden in the `setObject(forKey:expiry:)` method
//        expiry: .never,
//        // The maximum number of objects in memory the cache should hold
//        countLimit: 0,
//        // The maximum total cost that the cache can hold before it starts evicting objects, 0 for no limit
//        totalCostLimit: 0
//    )
//
//    var server: HLSCachingReverseProxyServer?
//
//    lazy var storage: Cache.Storage<String, Data>? = try? Cache.Storage<String, Data>(diskConfig: diskConfig, memoryConfig: memoryConfig, transformer: TransformerFactory.forCodable(ofType: Data.self))
//
//    /// Setups cache server for HLS streams
//    @objc public func setup(_ maxCacheSize: NSInteger) {
//        print("LOG + start local host")
//
//        GCDWebServer.setLogLevel(4)
//        let webServer = GCDWebServer()
//        let cache = PINCache.shared
//        cache.diskCache.byteLimit = UInt(maxCacheSize)
//        cache.diskCache.ageLimit = 30 * 24 * 60 * 60
//        let urlSession = URLSession.shared
//        server = HLSCachingReverseProxyServer(webServer: webServer, urlSession: urlSession, cache: cache)
//        server?.start(port: 8080)
//    }
//
//    @objc public func isVideoCached(_ url: URL) -> Bool {
//        let cache = PINCache.shared
//        // Check if the object exists in cache
//        if cache.containsObject(forKey: url.absoluteString) {
//            return true // The video is cached
//        } else {
//            return false // The video is not cached
//        }
//    }
//
//    @objc public func setMaxCacheSize(_ maxCacheSize: NSNumber?){
//        if let unsigned = maxCacheSize {
//            let _maxCacheSize = unsigned.uintValue
//            diskConfig = DiskConfig(name: "VideoPlayerCache", expiry: .date(Date().addingTimeInterval(3600*24*30)), maxSize: _maxCacheSize)
//        }
//    }
//
//    // MARK: - Logic
//
//    // @objc public func preCacheURL(_ url: URL, cacheKey: String?, videoExtension: String?, withHeaders headers: Dictionary<NSObject,AnyObject>, completionHandler: ((_ success:Bool) -> Void)?) {
//    //     self.completionHandler = completionHandler
//
//    //     let _key: String = cacheKey ?? url.absoluteString
//    //     // Make sure the item is not already being downloaded
//    //     if self._preCachedURLs[_key] == nil {
//    //         if let item = self.getCachingPlayerItem(url, cacheKey: _key, videoExtension: videoExtension, headers: headers){
//    //             if !self._existsInStorage {
//    //                 self._preCachedURLs[_key] = item
//    //                 item.download()
//    //             } else {
//    //                 self.completionHandler?(true)
//    //             }
//    //         } else {
//    //             self.completionHandler?(false)
//    //         }
//    //     } else {
//    //         self.completionHandler?(true)
//    //     }
//    // }
//
//    // @objc public func stopPreCache(_ url: URL, cacheKey: String?, completionHandler: ((_ success:Bool) -> Void)?){
//    //     let _key: String = cacheKey ?? url.absoluteString
//    //     if self._preCachedURLs[_key] != nil {
//    //         let playerItem = self._preCachedURLs[_key]!
//    //         playerItem.stopDownload()
//    //         self._preCachedURLs.removeValue(forKey: _key)
//    //         self.completionHandler?(true)
//    //         return
//    //     }
//    //     self.completionHandler?(false)
//    // }
//
//    /// Gets caching player item for normal playback.
//    @objc public func getCachingPlayerItemForNormalPlayback(_ url: URL, cacheKey: String?, videoExtension: String?, headers: [NSObject: AnyObject]) -> AVPlayerItem? {
//        let mimeTypeResult = getMimeType(url: url, explicitVideoExtension: videoExtension)
//        if mimeTypeResult.1 == "application/vnd.apple.mpegurl" {
//            let reverseProxyURL = server?.reverseProxyURL(from: url)!
//            let playerItem = AVPlayerItem(url: reverseProxyURL!)
//            return playerItem
//        } else {
//            return getCachingPlayerItem(url, cacheKey: cacheKey, videoExtension: videoExtension, headers: headers)
//        }
//    }
//
//    // Get a CachingPlayerItem either from the network if it's not cached or from the cache.
//    @objc private func getCachingPlayerItem(_ url: URL, cacheKey: String?, videoExtension: String?, headers: [NSObject: AnyObject]) -> CachingPlayerItem? {
//        let playerItem: CachingPlayerItem
//        let _key: String = cacheKey ?? url.absoluteString
//        // Fetch ongoing pre-cached url if it exists
//        if _preCachedURLs[_key] != nil {
//            playerItem = _preCachedURLs[_key]!
//            _preCachedURLs.removeValue(forKey: _key)
//        } else {
//            // Trying to retrieve a track from cache syncronously
//            let data = try? storage?.object(forKey: _key)
//            if data != nil {
//                // The file is cached.
//                _existsInStorage = true
//                let mimeTypeResult = getMimeType(url: url, explicitVideoExtension: videoExtension)
//                if mimeTypeResult.1.isEmpty {
//                    NSLog("Cache error: couldn't find mime type for url: \(url.absoluteURL). For this URL cache didn't work and video will be played without cache.")
//                    playerItem = CachingPlayerItem(url: url, cacheKey: _key, headers: headers)
//                } else {
//                    playerItem = CachingPlayerItem(data: data!, mimeType: mimeTypeResult.1, fileExtension: mimeTypeResult.0)
//                }
//            } else {
//                // The file is not cached.
//                playerItem = CachingPlayerItem(url: url, cacheKey: _key, headers: headers)
//                _existsInStorage = false
//            }
//        }
//        playerItem.delegate = self
//        return playerItem
//    }
//
//    // Remove all objects
//    @objc public func clearCache() {
//        try? storage?.removeAll()
//        _preCachedURLs = [String: CachingPlayerItem]()
//    }
//
//    private func getMimeType(url: URL, explicitVideoExtension: String?) -> (String, String) {
//        var videoExtension = url.pathExtension
//        if explicitVideoExtension != nil {
//            videoExtension = explicitVideoExtension!
//        }
//        var mimeType = ""
//        switch videoExtension {
//        case "m3u":
//            mimeType = "application/vnd.apple.mpegurl"
//        case "m3u8":
//            mimeType = "application/vnd.apple.mpegurl"
//        case "3gp":
//            mimeType = "video/3gpp"
//        case "mp4":
//            mimeType = "video/mp4"
//        case "m4a":
//            mimeType = "video/mp4"
//        case "m4p":
//            mimeType = "video/mp4"
//        case "m4b":
//            mimeType = "video/mp4"
//        case "m4r":
//            mimeType = "video/mp4"
//        case "m4v":
//            mimeType = "video/mp4"
//        case "m1v":
//            mimeType = "video/mpeg"
//        case "mpg":
//            mimeType = "video/mpeg"
//        case "mp2":
//            mimeType = "video/mpeg"
//        case "mpeg":
//            mimeType = "video/mpeg"
//        case "mpe":
//            mimeType = "video/mpeg"
//        case "mpv":
//            mimeType = "video/mpeg"
//        case "ogg":
//            mimeType = "video/ogg"
//        case "mov":
//            mimeType = "video/quicktime"
//        case "qt":
//            mimeType = "video/quicktime"
//        case "webm":
//            mimeType = "video/webm"
//        case "asf":
//            mimeType = "video/ms-asf"
//        case "wma":
//            mimeType = "video/ms-asf"
//        case "wmv":
//            mimeType = "video/ms-asf"
//        case "avi":
//            mimeType = "video/x-msvideo"
//        default:
//            mimeType = ""
//        }
//
//        return (videoExtension, mimeType)
//    }
//
////    ///Checks wheter pre cache is supported for given url.
////    @objc public func isPreCacheSupported(url: URL, videoExtension: String?) -> Bool{
////        let mimeTypeResult = getMimeType(url:url, explicitVideoExtension: videoExtension)
////        return !mimeTypeResult.1.isEmpty && mimeTypeResult.1 != "application/vnd.apple.mpegurl"
////    }
// }
//
//// MARK: - CachingPlayerItemDelegate
//
// extension CacheManager: CachingPlayerItemDelegate {
//    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingData data: Data) {
//        // A track is downloaded. Saving it to the cache asynchronously.
//        storage?.async.setObject(data, forKey: playerItem.cacheKey ?? playerItem.url.absoluteString, completion: { _ in })
//        completionHandler?(true)
//    }
//
//    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
//        /// Is called every time a new portion of data is received.
//        let percentage = Double(bytesDownloaded) / Double(bytesExpected) * 100.0
//        let str = String(format: "%.1f%%", percentage)
//        // NSLog("Downloading... %@", str)
//    }
//
//    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
//        /// Is called on downloading error.
//        NSLog("Error when downloading the file %@", error as NSError)
//        completionHandler?(false)
//    }
// }
//
////
////  HLSVideoCache.swift
////  HLSVideoCache
////
////  Created by Gary Newby on 19/08/2021.
////
//// m3u8 playlist parsing based on: https://github.com/StyleShare/HLSCachingReverseProxyServer
//// HLS Video caching using and embedded reverse proxy web server
//// Swapped PINCache for Cache
//// Added ability to save m3u8 manifest to disk for offline use
//// Fix keys too long for filenames error by hashing
//// Support segmented mp4 as well as ts

import Cache
import CryptoKit
import Foundation
import GCDWebServer
import PINCache

struct CacheItem: Codable {
    let data: Data
    let url: URL
    let mimeType: String
}

@objc public class CacheManager: NSObject {
    //    static let shared = HLSVideoCache()
    
    private let webServer: GCDWebServer
    private let urlSession: URLSession
    private let cache: Storage<String, CacheItem>
    private let originURLKey = "__hls_origin_url"
    private let port: UInt = 1234
    
    var completionHandler: ((_ success: Bool) -> Void)?
    
    @objc override public init() {
        self.webServer = GCDWebServer()
        self.urlSession = URLSession.shared
        
        // 200 mb disk cache
        let diskConfig = DiskConfig(name: "HLS_Video", expiry: .never, maxSize: 200 * 1024 * 1024)
        
        // 25 objects in memory
        let memoryConfig = MemoryConfig(expiry: .never, countLimit: 25, totalCostLimit: 25)
        
        guard let storage = try? Storage<String, CacheItem>(
            diskConfig: diskConfig,
            memoryConfig: memoryConfig,
            transformer: TransformerFactory.forCodable(ofType: CacheItem.self)
        ) else {
            fatalError("HLSVideoCache: unable to create cache")
        }
        
        self.cache = storage
        
        let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        print("documentDirectory", documentDirectory?.path ?? "--")
        super.init()
        
        addPlaylistHandler()
        start()
    }
    
    deinit {
        stop()
    }
    
    private func start() {
        guard !webServer.isRunning else { return }
        webServer.start(withPort: port, bonjourName: nil)
    }
    
    private func stop() {
        guard webServer.isRunning else { return }
        webServer.stop()
    }
    
    private func originURL(from request: GCDWebServerRequest) -> URL? {
        guard let encodedURLString = request.query?[originURLKey],
              let urlString = encodedURLString.removingPercentEncoding,
              let url = URL(string: urlString)
        else {
            print("Error: bad url")
            return nil
        }
        guard ["m3u8", "ts", "mp4", "m4s", "m4a", "m4v"].contains(url.pathExtension) else {
            print("Error: unsupported mime type")
            return nil
        }
        return url
    }
    
    // MARK: - Public functions
    
    func clearCache() throws {
        try cache.removeAll()
    }
    
    func reverseProxyURL(from originURL: URL) -> URL? {
        guard var components = URLComponents(url: originURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        
        let originURLQueryItem = URLQueryItem(name: originURLKey, value: originURL.absoluteString)
        components.queryItems = (components.queryItems ?? []) + [originURLQueryItem]
        
        return components.url
    }
    
    // MARK: - Request Handler
    
    private func addPlaylistHandler() {
        webServer.addHandler(forMethod: "GET", pathRegex: "^/.*\\.*$", request: GCDWebServerRequest.self) { [weak self] (request: GCDWebServerRequest, completion) in
            guard let self = self,
                  let originURL = self.originURL(from: request)
            else {
                return completion(GCDWebServerErrorResponse(statusCode: 400))
            }
            print("LOG + original url \(originURL)")
            if originURL.pathExtension == "m3u8" {
                // Return cached m3u8 manifest
                if let item = self.cachedDataItem(for: originURL),
                   let playlistData = self.reverseProxyPlaylist(with: item, forOriginURL: originURL)
                {
                    return completion(GCDWebServerDataResponse(data: playlistData, contentType: item.mimeType))
                }
                
                // Cache m3u8 manifest
                let task = self.urlSession.dataTask(with: originURL) { data, response, _ in
                    guard let data = data,
                          let response = response,
                          let mimeType = response.mimeType
                    else {
                        return completion(GCDWebServerErrorResponse(statusCode: 500))
                    }
                    
                    let item = CacheItem(data: data, url: originURL, mimeType: mimeType)
                    self.saveCacheDataItem(item)
                    
                    if let playlistData = self.reverseProxyPlaylist(with: item, forOriginURL: originURL) {
                        return completion(GCDWebServerDataResponse(data: playlistData, contentType: item.mimeType))
                    } else {
                        return completion(GCDWebServerErrorResponse(statusCode: 500))
                    }
                }
                
                task.resume()
                
            } else {
                // Return cached segment
                if let cachedItem = self.cachedDataItem(for: originURL) {
                    return completion(GCDWebServerDataResponse(data: cachedItem.data, contentType: cachedItem.mimeType))
                }
                
                // Cache segment
                let task = self.urlSession.dataTask(with: originURL) { data, response, _ in
                    guard let data = data,
                          let response = response,
                          let contentType = response.mimeType
                    else {
                        return completion(GCDWebServerErrorResponse(statusCode: 500))
                    }
                    
                    let mimeType = originURL.absoluteString.contains(".mp4") ? "video/mp4" : response.mimeType!
                    let item = CacheItem(data: data, url: originURL, mimeType: mimeType)
                    self.saveCacheDataItem(item)
                    
                    return completion(GCDWebServerDataResponse(data: data, contentType: contentType))
                }
                
                task.resume()
            }
        }
    }
    
    @objc public func precache(originURL: URL) {
        if originURL.pathExtension == "m3u8" {
            // Return cached m3u8 manifest
            if let item = cachedDataItem(for: originURL),
               let playlistData = reverseProxyPlaylist(with: item, forOriginURL: originURL)
            {
                return
            }
            
            // Cache m3u8 manifest
            let task = urlSession.dataTask(with: originURL) { data, response, _ in
                guard let data = data,
                      let response = response,
                      let mimeType = response.mimeType
                else {
                    return
                }
                
                let item = CacheItem(data: data, url: originURL, mimeType: mimeType)
                self.saveCacheDataItem(item)
                
                if let playlistData = self.reverseProxyPlaylist(with: item, forOriginURL: originURL) {
                    return
                } else {
                    return
                }
            }
            
            task.resume()
            
        } else {
            // Return cached segment
            if let cachedItem = cachedDataItem(for: originURL) {
                return
            }
            
            // Cache segment
            let task = urlSession.dataTask(with: originURL) { data, response, _ in
                guard let data = data,
                      let response = response,
                      let contentType = response.mimeType
                else {
                    return
                }
                
                let mimeType = originURL.absoluteString.contains(".mp4") ? "video/mp4" : response.mimeType!
                let item = CacheItem(data: data, url: originURL, mimeType: mimeType)
                self.saveCacheDataItem(item)
            }
            
            task.resume()
        }
    }
    
    // MARK: - Manipulating Playlist
    
    private func reverseProxyPlaylist(with item: CacheItem, forOriginURL originURL: URL) -> Data? {
        let original = String(data: item.data, encoding: .utf8)
        let parsed = original?
            .components(separatedBy: .newlines)
            .map { line in processPlaylistLine(line, forOriginURL: originURL) }
            .joined(separator: "\n")
        
        return parsed?.data(using: .utf8)
    }
    
    private func processPlaylistLine(_ line: String, forOriginURL originURL: URL) -> String {
        guard !line.isEmpty else { return line }
        
        if line.hasPrefix("#") {
            return lineByReplacingURI(line: line, forOriginURL: originURL)
        }
        
        if let originalSegmentURL = absoluteURL(from: line, forOriginURL: originURL),
           let reverseProxyURL = reverseProxyURL(from: originalSegmentURL)
        {
            return reverseProxyURL.absoluteString
        }
        return line
    }
    
    private func lineByReplacingURI(line: String, forOriginURL originURL: URL) -> String {
        let uriPattern = try! NSRegularExpression(pattern: "URI=\"([^\"]*)\"")
        let lineRange = NSRange(location: 0, length: line.count)
        guard let result = uriPattern.firstMatch(in: line, options: [], range: lineRange) else { return line }
        
        let uri = (line as NSString).substring(with: result.range(at: 1))
        guard let absoluteURL = absoluteURL(from: uri, forOriginURL: originURL) else { return line }
        guard let reverseProxyURL = reverseProxyURL(from: absoluteURL) else { return line }
        
        return uriPattern.stringByReplacingMatches(in: line, options: [], range: lineRange, withTemplate: "URI=\"\(reverseProxyURL.absoluteString)\"")
    }
    
    private func absoluteURL(from line: String, forOriginURL originURL: URL) -> URL? {
        if line.hasPrefix("http://") || line.hasPrefix("https://") {
            return URL(string: line)
        }
        
        guard let scheme = originURL.scheme,
              let host = originURL.host
        else {
            print("Error: bad url")
            return nil
        }
        
        let path: String
        if line.hasPrefix("/") {
            path = line
        } else {
            path = originURL.deletingLastPathComponent().appendingPathComponent(line).path
        }
        
        return URL(string: scheme + "://" + host + path)?.standardized
    }
    
    // MARK: - Caching
    
    private func cachedDataItem(for resourceURL: URL) -> CacheItem? {
        let key = cacheKey(for: resourceURL)
        let item = try? cache.object(forKey: key)
        return item
    }
    
    private func saveCacheDataItem(_ item: CacheItem) {
        let key = cacheKey(for: item.url)
        try? cache.setObject(item, forKey: key)
    }
    
    private func cacheKey(for resourceURL: URL) -> String {
        // Hash key to avoid file name too long errors
        if #available(iOS 13.0, *) {
            SHA256
                .hash(data: Data(resourceURL.absoluteString.utf8))
                .map { String(format: "%02hhx", $0) }
                .joined()
        }
        return resourceURL.absoluteString
    }
}

public extension CacheManager {
    @objc func getCachingPlayerItemForNormalPlayback(_ url: URL, cacheKey: String?, videoExtension: String?, headers: [NSObject: AnyObject]) -> AVPlayerItem? {
        let newUrl = reverseProxyURL(from: url)
        let item = AVPlayerItem(url: newUrl!)
        item.preferredForwardBufferDuration = 10
        return item
    }
    
    @objc func isVideoCached(_ url: URL) -> Bool {
        let cache = PINCache.shared
        // Check if the object exists in cache
        if cache.containsObject(forKey: url.absoluteString) {
            return true // The video is cached
        } else {
            return false // The video is not cached
        }
    }
}
