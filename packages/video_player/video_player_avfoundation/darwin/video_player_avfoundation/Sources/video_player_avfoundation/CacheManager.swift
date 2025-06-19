//
//  HLSVideoCache.swift
//  HLSVideoCache
//
//  Created by Gary Newby on 19/08/2021.
//
// m3u8 playlist parsing based on: https://github.com/StyleShare/HLSCachingReverseProxyServer
// HLS Video caching using and embedded reverse proxy web server
// Swapped PINCache for Cache
// Added ability to save m3u8 manifest to disk for offline use
// Fix keys too long for filenames error by hashing
// Support segmented mp4 as well as ts

import Cache
import CryptoKit
import Foundation
import GCDWebServer
import PINCache
import AVFoundation

struct CacheItem: Codable {
    let data: Data
    let url: URL
    let mimeType: String
}

enum VideoQuality {
    case p480
    case p720
    case p1080
}

@objc public class CacheManager: NSObject {
    //    static let shared = HLSVideoCache()
    
    private let webServer: GCDWebServer
    private let urlSession: URLSession
    private let cache: Storage<String, CacheItem>
    private let originURLKey = "__hls_origin_url"
    private let port: UInt = 1234
    private var currentVideoQuality = VideoQuality.p480
    
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
                let lastPath = originURL.lastPathComponent
                if lastPath.contains("480") {
                    currentVideoQuality = VideoQuality.p480
                } else if lastPath.contains("720") {
                    currentVideoQuality = VideoQuality.p720
                } else if lastPath.contains("1080") {
                    currentVideoQuality = VideoQuality.p1080
                } else {
                    print("⚪️ Unknown quality")
                }
                
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
        guard originURL.pathExtension == "m3u8" else { return }

        let baseURL = originURL.deletingLastPathComponent()

        let qualityPrefix: String
        switch self.currentVideoQuality {
        case .p480: qualityPrefix = "480"
        case .p720: qualityPrefix = "720"
        case .p1080: qualityPrefix = "1080"
        }

        let qualityM3U8URL = baseURL.appendingPathComponent("\(qualityPrefix).m3u8")
        let tsSegmentURL = baseURL.appendingPathComponent("\(qualityPrefix)p_000.ts")

        // Step 1: Cache index.m3u8 if needed
        func cacheIndexIfNeeded(completion: @escaping () -> Void) {
            if let _ = cachedDataItem(for: originURL) {
                print("✅ index.m3u8 already cached")
                completion()
                return
            }

            urlSession.dataTask(with: originURL) { data, response, _ in
                guard let data = data,
                      let response = response,
                      let mimeType = response.mimeType else {
                    completion() // Proceed anyway
                    return
                }

                let item = CacheItem(data: data, url: originURL, mimeType: mimeType)
                self.saveCacheDataItem(item)
                print("✅ Cached index.m3u8")
                completion()
            }.resume()
        }

        // Step 2: Cache quality.m3u8 if needed
        func cacheQualityIfNeeded(completion: @escaping () -> Void) {
            if let _ = cachedDataItem(for: qualityM3U8URL) {
                print("✅ \(qualityPrefix).m3u8 already cached")
                completion()
                return
            }

            urlSession.dataTask(with: qualityM3U8URL) { data, response, _ in
                guard let data = data,
                      let response = response,
                      let mimeType = response.mimeType else {
                    completion()
                    return
                }

                let item = CacheItem(data: data, url: qualityM3U8URL, mimeType: mimeType)
                self.saveCacheDataItem(item)
                print("✅ Cached \(qualityPrefix).m3u8")
                completion()
            }.resume()
        }

        // Step 3: Cache ts segment if needed
        func cacheFirstTSIfNeeded() {
            if let _ = cachedDataItem(for: tsSegmentURL) {
                print("✅ \(tsSegmentURL.lastPathComponent) already cached")
                return
            }

            urlSession.dataTask(with: tsSegmentURL) { data, response, _ in
                guard let data = data,
                      let response = response,
                      let mimeType = response.mimeType else { return }

                let item = CacheItem(data: data, url: tsSegmentURL, mimeType: mimeType)
                self.saveCacheDataItem(item)
                print("✅ Cached \(tsSegmentURL.lastPathComponent)")
            }.resume()
        }

        // Start the sequence
        cacheIndexIfNeeded {
            cacheQualityIfNeeded {
                cacheFirstTSIfNeeded()
            }
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
    
    private var selectedAudioOption: AVMediaSelectionOption?
    private var currentPlayerItem: AVPlayerItem?
    
    private func selectAudioTrack(displayName: String) {
        guard let playerItem = currentPlayerItem,
              let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
        group.options.map { element in
            print("LOG + supposet lang \(element.displayName)")
        }
        
        if let selectedOption = group.options.first(where: { $0.displayName == displayName }) {
            currentPlayerItem?.select(selectedOption, in: group)
        }
    }
}

public extension CacheManager {
    @objc func getCachingPlayerItemForNormalPlayback(_ url: URL, cacheKey: String?, videoExtension: String?, headers: [NSObject: AnyObject]) -> AVPlayerItem? {
        let newUrl = reverseProxyURL(from: url)
        currentPlayerItem = AVPlayerItem(url: newUrl!)
        currentPlayerItem?.preferredForwardBufferDuration = 10
        
        guard let asset = currentPlayerItem?.asset as? AVURLAsset else {
            print("LOG + video player: keep access")
            return currentPlayerItem
        }
        
        asset.loadValuesAsynchronously(forKeys: ["availableMediaCharacteristicsWithMediaSelectionOptions"]) {
            if let videoGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .visual) {
                
                for option in videoGroup.options {
                    let displayName = option.displayName
                    
                    print("LOG + video player: Quality Option: \(displayName)")
                }
                
                // 🔸 Example: Select first available option (you can match by name or resolution)
                if let selectedOption = videoGroup.options.first {
                    self.currentPlayerItem?.select(selectedOption, in: videoGroup)
                    print("LOG + video player: Selected video quality: \(selectedOption.displayName)")
                }
            } else {
                print("LOG + video player: No visual media selection group found")
            }
        }

        return currentPlayerItem
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
    
    @objc func setDubbing(_ name: String) {
        print("LOG + set dubbing \(name)")
        selectAudioTrack(displayName: name)
    }
}
