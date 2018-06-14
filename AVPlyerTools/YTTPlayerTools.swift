//
//  YTTPlayerTools.swift
//  AVPlyerTools
//
//  Created by qiuweniOS on 2018/6/13.
//  Copyright © 2018年 AndyCuiYTT. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

protocol YTTPlayerProtocol {
    
    func player(_ player: YTTPlayerTools, currentTime: TimeInterval, totalTime: TimeInterval)
    
    func player(_ player: YTTPlayerTools, cacheTime: TimeInterval, totalTime: TimeInterval)
    
    func playerStartPlay(_ player: YTTPlayerTools)
    
    func player(_ player: YTTPlayerTools, loadFailedAt index: Int)
    
    func numberOfMedia(_ player: YTTPlayerTools) -> Int
    
    func player(_ player: YTTPlayerTools, playAt index: Int) -> YTTMediaInfo
}

extension YTTPlayerProtocol {
    
    func player(_ player: YTTPlayerTools, currentTime: TimeInterval, totalTime: TimeInterval){}
    
    func player(_ player: YTTPlayerTools, cacheTime: TimeInterval, totalTime: TimeInterval){}
    
    func playerStartPlay(_ player: YTTPlayerTools){}
    
    func player(_ player: YTTPlayerTools, loadFailedAt index: Int){}
}

struct YTTMediaInfo {
    let url: String!
    let title: String?
    let singer: String?
    let image: UIImage?
    let totalTime: NSNumber? = NSNumber(value: 0.0)
    let currentTime: NSNumber? = NSNumber(value: 0.0)
    
}


class YTTPlayerTools: NSObject {

    private(set) var player: AVPlayer?
    var delegate: YTTPlayerProtocol?
    private var currentPlayItem: AVPlayerItem?
    private(set) var currentIndex = 0
    
   
    
    
    init(allowBackground: Bool = true) {
        super.init()
        UIApplication.shared.beginReceivingRemoteControlEvents()
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
        player = AVPlayer()
        NotificationCenter.default.addObserver(self, selector: #selector(finish(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: DispatchQueue.main, using: { [weak self] (cmTime) in

            if let totalTime = self?.currentPlayItem?.duration {
//                print("\(cmTime.seconds)-------")
//                print(Float(cmTime.value) / Float(cmTime.timescale))
//                CMTimeGetSeconds(cmTime)
                self?.delegate?.player(self!, currentTime: cmTime.seconds, totalTime: totalTime.seconds)
            }
        })
    }
    
    
    @objc func play() {
        player?.play()
        delegate?.playerStartPlay(self)
        
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: self.currentPlayItem?.currentTime().seconds ?? 0)
            dic[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: self.currentPlayItem?.duration.seconds ?? 0)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
    }
    
    @objc func pause() {
        player?.pause()
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
            dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: self.currentPlayItem?.currentTime().seconds ?? 0)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
       
        
    }
    
    func rate(_ rate: Float) {
        player?.rate = rate
        if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            dic[MPNowPlayingInfoPropertyPlaybackRate] = rate
            MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
        }
    }
    
    @objc func next() {
        
        if let count = delegate?.numberOfMedia(self) {
            if currentIndex + 1 < count {
                currentIndex = currentIndex + 1
            } else if currentIndex + 1 == count {
                currentIndex = 0
            }
        }
        
        if let media = delegate?.player(self, playAt: currentIndex) {
            exchagePlayItem(media)
        }
    }
    
    @objc func previous() {
        
        if currentIndex > 0 {
            currentIndex = currentIndex - 1
        }else if currentIndex == 0 {
            if let count = delegate?.numberOfMedia(self) {
                currentIndex = count
            }
        }
        
        if let media = delegate?.player(self, playAt: currentIndex) {
            exchagePlayItem(media)
        }
    }
    
    
    func currentTime(_ second: TimeInterval) {
        
        if let totalTime = currentPlayItem?.duration {
            let time = CMTimeMakeWithSeconds(second, totalTime.timescale)
            player?.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
//            player?.seek(to: kCMTimeZero)
            if var dic = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                dic[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: second)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = dic
            }
        }
    }
    
    @objc private func finish(_ notification: Notification) {
        next()
    }
    
    func exchagePlayItem(atIndex index: Int) {
        if let media = delegate?.player(self, playAt: index) {
            currentIndex = index
            exchagePlayItem(media)
        }
    }
    
    private func exchagePlayItem(_ mediaInfo: YTTMediaInfo) {
        if let url = URL(string: mediaInfo.url) {
            currentPlayItem?.removeObserver(self, forKeyPath: "status")
            currentPlayItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
            let asset = AVAsset(url: url)
            let playItem = AVPlayerItem(asset: asset)
            currentPlayItem = playItem
            // 监听 playerItem 状态变化
            currentPlayItem?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
            // 监听缓存时间
            currentPlayItem?.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
            
            player?.replaceCurrentItem(with: playItem)
            setLockScreenPlayingInfo(mediaInfo)
        }
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if object is AVPlayerItem {
            if keyPath == "status" {
                if let playerItem = object as? AVPlayerItem {
                    switch playerItem.status {
                    case .readyToPlay:
                        self.play()
                    case .failed:
                        delegate?.player(self, loadFailedAt: currentIndex)
                        print("加载失败")
                    default:
                        print("加载失败")
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
        currentPlayItem?.removeObserver(self, forKeyPath: "status")
        currentPlayItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        MPRemoteCommandCenter.shared().playCommand.removeTarget(self, action: #selector(play))
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(self, action: #selector(next))
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(self, action: #selector(pause))
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(self, action: #selector(previous))
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
    
    
    
    
}