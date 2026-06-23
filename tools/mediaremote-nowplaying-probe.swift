import Foundation

typealias MRNowPlayingBlock = @convention(block) (CFDictionary?) -> Void
typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, MRNowPlayingBlock) -> Void
typealias MRGetLocalOrigin = @convention(c) () -> UnsafeRawPointer?
typealias MRGetNowPlayingInfoForOrigin = @convention(c) (UnsafeRawPointer?, DispatchQueue, MRNowPlayingBlock) -> Void

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW) else {
    print("dlopen failed")
    exit(1)
}
if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
    let getInfo = unsafeBitCast(sym, to: MRGetNowPlayingInfo.self)
    let sem = DispatchSemaphore(value: 0)
    let block: MRNowPlayingBlock = { dict in
        print("mode=MRMediaRemoteGetNowPlayingInfo")
        if let dict = dict as? [String: Any] {
            for key in dict.keys.sorted() {
                if key == "kMRMediaRemoteNowPlayingInfoArtworkData" {
                    let bytes = (dict[key] as? Data)?.count ?? 0
                    print("\(key)=<\(bytes) bytes>")
                } else {
                    print("\(key)=\(dict[key] ?? "nil")")
                }
            }
        } else {
            print("nil")
        }
        sem.signal()
    }
    getInfo(.global(qos: .userInitiated), block)
    _ = sem.wait(timeout: .now() + 5)
    exit(0)
}

guard let originSym = dlsym(handle, "MRMediaRemoteGetLocalOrigin"),
      let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfoForOrigin") else {
    print("MediaRemote symbols not found")
    exit(1)
}

let copyLocalOrigin = unsafeBitCast(originSym, to: MRGetLocalOrigin.self)
let getInfo = unsafeBitCast(infoSym, to: MRGetNowPlayingInfoForOrigin.self)
let origin = copyLocalOrigin()
print("origin=\(String(describing: origin))")

let sem = DispatchSemaphore(value: 0)

let block: MRNowPlayingBlock = { dict in
    guard let dict = dict as? [String: Any] else {
        print("nil")
        sem.signal()
        return
    }
    for key in dict.keys.sorted() {
        print("\(key)=\(dict[key] ?? "nil")")
    }
    sem.signal()
}
getInfo(origin, .global(qos: .userInitiated), block)

_ = sem.wait(timeout: .now() + 5)
