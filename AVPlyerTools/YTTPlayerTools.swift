//
//  YTTPlayerTools.swift
//  AVPlyerTools
//
//  Created by AndyCui on 2018/6/13.
//  Copyright © 2018年 AndyCuiYTT. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

protocol YTTPlayerProtocol {
    
    func player(_ player: YTTPlayerTools, currentTime: TimeInterval, totalTime: TimeInterval)
    
    func player(_ player: YTTPlayerTools, cacheTime: TimeInterval, totalTime: TimeInterval)
    
    func player(_ player: YTTPlayerTools, startPlayAt index: Int)
    
    func player(_ player: YTTPlayerTools, playFailedAt index: Int)
    
    func player(_ player: YTTPlayerTools, playToEndTimeAt index: Int)
    
    func numberOfMedia(_ player: YTTPlayerTools) -> Int
    
    func player(_ player: YTTPlayerTools, playAt index: Int) -> YTTMediaInfo
}

extension YTTPlayerProtocol {
    
    func player(_ player: YTTPlayerTools, currentTime: TimeInterval, totalTime: TimeInterval){}
    
    func player(_ player: YTTPlayerTools, cacheTime: TimeInterval, totalTime: TimeInterval){}
    
    func player(_ player: YTTPlayerTools, startPlayAt index: Int){}
    
    func player(_ player: YTTPlayerTools, playFailedAt index: Int){}
    
    func player(_ player: YTTPlayerTools, playToEndTimeAt index: Int){}
}

struct YTTMediaInfo {
    let url: String!
    let title: String?
    let singer: String?
    let image: UIImage?
    let totalTime: NSNumber? = NSNumber(value: 0.0)
    let currentTime: NSNumber? = NSNumber(value: 0.0)
    
}

/**
 *  开启子线程,降换歌放到子线程
 *  添加 AVAsset 检测,排除不可播放音频
 */

class YTTPlayerTools: NSObject {

    var delegate: YTTPlayerProtocol?
    private var currentPlayItem: AVPlayerItem?
    private var currentIndex = 0
    private var bgTask: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    private var timeObserver: Any?
    private(set) lazy var player: AVPlayer = {
        return AVPlayer()
    }()
    
    
    init(allowBackground: Bool = true) {
        super.init()
        // 声明接收Remote Control事件
        UIApplication.shared.beginReceivingRemoteControlEvents()
        // 响应 Remote Control事件
        MPRemoteCommandCenter.shared().playCommand.addTarget(self, action: #selector(play))
        
        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget(self, action: #selector(next))
        
        MPRemoteCommandCenter.shared().pauseCommand.addTarget(self, action: #selector(pause))
        
        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget(self, action: #selector(previous))
        
        if allowBackground {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(true)
                try session.setCategory(AVAudioSessionCategoryPlayback)
            } catch {
                print(error)
            }
        }
        
        // 播放结束通知
        NotificationCenter.default.addObserver(self, selector: #selector(finish(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: DispatchQueue.main, using: { [weak self] (cmTime) in

            if cmTime.seconds > 0 && cmTime.seconds < 2 {
                if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: self?.currentPlayItem?.currentTime().seconds ?? 0)
                    dic[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: self?.currentPlayItem?.duration.seconds ?? 0)
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
                }
            }

            if let totalTime = self?.currentPlayItem?.duration {
//                print("\(cmTime.seconds)-------")
//                print(Float(cmTime.value) / Float(cmTime.timescale))
//                CMTimeGetSeconds(cmTime)
                self?.delegate?.player(self!, currentTime: cmTime.seconds, totalTime: totalTime.seconds)
            }
        })
        
    }
    
    
    
    @objc func play() {
        player.play()
        delegate?.player(self, startPlayAt: currentIndex)
        
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
    }
    
    @objc func pause() {
        player.pause()
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: self.currentPlayItem?.currentTime().seconds ?? 0)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
       
        
    }
    
    func rate(_ rate: Float) {
        player.rate = rate
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = rate
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
    }
    
    @objc func next() {
        if let count = delegate?.numberOfMedia(self) {
            if currentIndex + 1 < count {
                exchagePlayItem(atIndex: currentIndex + 1)
            } else if currentIndex + 1 == count {
                exchagePlayItem(atIndex: 0)
            }
        }
    }
    
    @objc func previous() {
        
        if currentIndex > 0 {
            exchagePlayItem(atIndex: currentIndex - 1)
        }else if currentIndex == 0 {
            if let count = delegate?.numberOfMedia(self) {
                exchagePlayItem(atIndex: count - 1)
            }
        }
    
    }
    
    
    func currentTime(_ second: TimeInterval) {
        
        if let totalTime = currentPlayItem?.duration {
            guard totalTime.seconds > second else {
                return
            }
            pause()
            let time = CMTimeMakeWithSeconds(second, totalTime.timescale)
            player.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: { (flag) in
                self.play()
            })
            if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: second)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
            }
        }
    }
    
    @objc private func finish(_ notification: Notification) {
        delegate?.player(self, playToEndTimeAt: currentIndex)
    }
    
    func exchagePlayItem(atIndex index: Int) {
        if let media = delegate?.player(self, playAt: index) {
            currentIndex = index
            
            DispatchQueue.init(label: "com.andy.cui.player", qos: .default, attributes: .concurrent).async {
                self.exchagePlayItem(media)
            }
        }
    }
    
    private func exchagePlayItem(_ mediaInfo: YTTMediaInfo) {
        if let url = URL(string: mediaInfo.url) {
            let asset = AVAsset(url: url)
            guard asset.isPlayable else{
                delegate?.player(self, playFailedAt: currentIndex)
                return
            }
            let playItem = AVPlayerItem(asset: asset)
            currentPlayItem?.removeObserver(self, forKeyPath: "status")
            currentPlayItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
            
            // 监听 playerItem 状态变化
            playItem.addObserver(self, forKeyPath: "status", options: .new, context: nil)
            // 监听缓存时间
            playItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
            DispatchQueue.main.async {
                self.player.replaceCurrentItem(with: playItem)
            }
             
            currentPlayItem = playItem
            setLockScreenPlayingInfo(mediaInfo)
        }
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if object is AVPlayerItem {
            if keyPath == "status" {
                if let playerItem = object as? AVPlayerItem {
                    switch playerItem.status {
                    case .readyToPlay:
                        DispatchQueue.main.async {
                            self.play()
                        }
                    case .failed:
                        DispatchQueue.main.async {
                            self.delegate?.player(self, playFailedAt: self.currentIndex)
                        }
                        print("加载失败")
                    default:
                        print("加载")
                    }
                }
            }
            
            if keyPath == "loadedTimeRanges" {
                if let playerItem = object as? AVPlayerItem {
                    if let timeRange = playerItem.loadedTimeRanges.first as? CMTimeRange {
                        delegate?.player(self, cacheTime: timeRange.start.seconds + timeRange.duration.seconds, totalTime: playerItem.duration.seconds)
                    }
                }
            }
        }
    }
    
    func setLockScreenPlayingInfo(_ info: YTTMediaInfo) {
        // Now Playing Center可以在锁屏界面展示音乐的信息，也达到增强用户体验的作用。
        // https://www.jianshu.com/p/458b67f84f27
        var infoDic: [String : Any] = [:]
        infoDic[MPMediaItemPropertyTitle] = info.title
        infoDic[MPMediaItemPropertyArtist] = info.singer
        
        if let img = info.image {
            infoDic[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: img)
        }
        
        infoDic[MPMediaItemPropertyPlaybackDuration] = info.totalTime
        infoDic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = info.currentTime
        infoDic[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = infoDic
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        currentPlayItem?.removeObserver(self, forKeyPath: "status")
        currentPlayItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        MPRemoteCommandCenter.shared().playCommand.removeTarget(self, action: #selector(play))
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(self, action: #selector(next))
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(self, action: #selector(pause))
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(self, action: #selector(previous))
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
    
    
    
}
