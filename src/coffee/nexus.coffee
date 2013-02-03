# Manages the user's personal botnet data.
#
# This is a distributed command and control center. 
class Nexus
  # @param {Dropbox.Chrome} dropboxChrome
  constructor: (@dropboxChrome) ->
    @_hosts = null
    @_hostsVersionTag = null  # Revision of hosts directory.
    @_hostsCallbacks = []
    @_hostId = null

    @_listeningForHostChanges = false
    @_listeningForRtc = false

    @_rtc = {}
    @_rtcData = {}
    @_rtcWrite = {}
    @_rtcVersionTags = {}
    @_rtcVideo = {}
    @_rtcDirVersionTag = null

    @onHostsChange = new Dropbox.EventSource
    @onRtc = new Dropbox.EventSource

  # @property {Dropbox.EventSource<Object<String, HostInfo>>}
  onHostsChange: null

  # @property {Dropbox.EventSource<Array[HostInfo, video stream]>}
  onRtc: null

  # @param {function(Array<HostInfo>)} callback
  # @return {Nexus} this
  hosts: (callback) ->
    if @_hosts
      callback @_hosts
      return @

    @_hostsCallbacks.push callback
    return @

  # @param {HostInfo} hostInfo
  # @param {function(?Dropbox.ApiError)} callback
  # @return {Nexus} this
  registerHost: (hostInfo, callback) ->
    hostInfo.setUserAgent navigator.userAgent
    @dropboxChrome.client (client) =>
      # NOTE: mkdir builds the host directory and the nested rtc directory in
      #       one call (acts like `mkdir -p`)
      client.mkdir @_rtcDir(hostInfo.id), (error, hostDirStat) =>
        if error
          callback error, null
          return
          
        infoFile = @_infoFile hostInfo.id
        infoString = JSON.stringify(hostInfo.json())
        client.writeFile infoFile, infoString, (error, stat) =>
          if error
            callback error
            return
          hostInfo.setInfoStat stat
          @setHostId hostInfo.id
          callback null
    @
  
  # @param {String} hostId
  # @return {Nexus} this
  setHostId: (hostId) ->
    @_hostId = hostId
    if hostId
      @_listenForHostChanges()
      @_listenForRtc()
    @

  # Ask for the video of a remote host.
  callHost: (calleeHostInfo) ->
    return if @_rtc[calleeHostInfo.id]

    rtc = @_initRtc calleeHostInfo.id
    rtc.callHost calleeHostInfo.id, @_hostId

  # Sends RTC sync data to a peer.
  #
  # Called by the RTC connection controller.
  #
  # @param {RTC} rtc connection to partner
  # @param {Object<String, Object>} data JSON-able packet
  sendRtcSync: (rtc, data) ->
    hostId = rtc.peerHostId()
    rtcData = @_rtcData[hostId]
    messageId = rtcData.lastOutId + 1
    rtcData.lastOutId = messageId
    rtcData.sync.push [messageId, data]
    return if @_rtcWrite[hostId]

    writeOp = =>
      @_rtcWrite[hostId] = false
      @dropboxChrome.client (client) =>
        lastSentId = rtcData.sync[rtcData.sync.length - 1][0]
        jsonString = JSON.stringify rtcData
        client.writeFile rtc.peerDataFile(), jsonString, (error, stat) =>
          if error
            # TODO(pwnall): do something smarter about the error
            console.log error

          # If we got more data while writing, send it out soon.
          if lastSentId isnt rtcData.sync[rtcData.sync.length - 1][0]
            setTimeout writeOp, @writeCoalesceMs
          else
            @_rtcWrite[hostId] = false
    @_rtcWrite[hostId] = true
    setTimeout writeOp, @writeCoalesceMs

  # Fires off the polling loop that emits host change events.
  #
  # @return {Nexus} this
  _listenForHostChanges: ->
    return if @_listeningForHostChanges
    @_listeningForHostChanges = true
    pollStep = =>
      @_updateHosts =>
        setTimeout pollStep, @pollingCooldownMs
    pollStep()
    @

  # @private
  # Use the Nexus#hosts public API instead.
  #
  # @param {function()} callback
  _updateHosts: (callback) ->
    @_refetchHosts (error, hosts, hasChanges) =>
      if error
        console.log error
        # TODO(pwnall): do something intelligent
        @_hosts = {}
      else
        @_hosts = hosts

      if @_hostsCallbacks
        callbacks = @_hostsCallbacks
        @_hostsCallbacks = null
        for hostCallback in callbacks
          hostCallback @_hosts

      @onHostsChange.dispatch @_hosts if hasChanges
      callback()
    @

  # @private
  # Use the Nexus#hosts public API instead.
  #
  # @param {function(?Dropbox.ApiError, ?Object<String, HostInfo>, Boolean)}
  #   callback
  # @return {Nexus} this
  _refetchHosts: (callback) ->
    @dropboxChrome.client (client) =>
      options = readDir: true, httpCache: true
      options.versionTag = @_hostsVersionTag if @_hostsVersionTag
      client.stat '/',  options, (error, rootStat, hostDirStats) =>
        if error
          if error.status is 304
            # Nothing changed.
            callback null, @_hosts, false
          else
            callback error, null, null
          return
        
        @_hostsVersionTag = rootStat.versionTag
        hosts = {}
        readQueue = []
        for hostDirStat in hostDirStats
          hostId = hostDirStat.name
          if @_hosts and (oldHostInfo = @_hosts[hostId]) and
              oldHostInfo.dirVersionTag is hostDirStat.versionTag
            hosts[hostId] = @_hosts[hostId]
          else
            readQueue.push hostDirStat

        if readQueue.length is 0
          callback null, @_hosts, false
          return

        iterator = (hostDirStat, callback) =>
          @_refreshHost hosts, hostDirStat, callback
        async.forEachLimit readQueue, @dropboxReadLimit, iterator, (error) ->
          if error
            callback error, null, true
          else
            callback null, hosts, true
    @

  # @param {Object<String, HostInfo>} hosts
  # @param {Dropbox.Stat} hostDirStat
  # @param {function(?Dropbox.ApiError)} callback
  # @return {Nexus} this
  _refreshHost: (hosts, hostDirStat, callback) ->
    @dropboxChrome.client (client) =>
      hostId = hostDirStat.name
      infoFile = @_infoFile hostId
      client.readFile infoFile, httpCache: true, (error, string, stat) =>
        if error
          callback error
        else
          try
            infoJson = JSON.parse string
          catch jsonError
            callback jsonError
            return
          hosts[hostId] = HostInfo.parse infoJson, stat, hostDirStat
          callback null
    @


  # @param {String} hostId
  # @return {String}
  _infoFile: (hostId) ->
    "#{hostId}/info.json"

  # @param {HostInfo} hostInfo
  # @return {String}
  _rtcDir: (hostId) ->
    "#{hostId}/rtc"

  # Fires off the polling loop that emits rtc events.
  #
  # @private
  # @return {Nexus} this
  _listenForRtc: ->
    return if @_listeningForRtc
    @_listeningForRtc = true
    pollStep = =>
      @_refetchRtc (error) =>
        if error
          # TODO(pwnall): do something smarter about the error
          console.log error
        setTimeout pollStep, @pollingCooldownMs
    pollStep()

  # @private
  #
  # @param {function(?Dropbox.ApiError)} callback
  # @return {Nexus} this
  _refetchRtc: (callback) ->
    rtcDir = @_rtcDir @_hostId
    @dropboxChrome.client (client) =>
      options = readDir: true, httpCache: true
      options.versionTag = @_rtcDirVersionTag if @_rtcDirVersionTag
      client.stat rtcDir,  options, (error, rtcDirStat, rtcStats) =>
        if error
          if error.status is 304
            # Nothing changed.
            callback null
          else
            callback error
          return
        
        @_rtcDirVersionTag = rtcDirStat.versionTag
        readQueue = []
        for rtcStat in rtcStats
          fileName = rtcStat.name
          if @_rtcVersionTags[fileName] is rtcStat.versionTag
            continue
          else
            readQueue.push rtcStat

        if readQueue.length is 0
          callback null
          return

        iterator = (rtcStat, callback) => @_refreshRtc rtcStat, callback
        async.forEachLimit readQueue, @dropboxReadLimit, iterator, (error) ->
          if error
            callback error
          else
            callback null
    @

  # @param {Dropbox.Stat} rtcStat
  # @param {function(?Dropbox.ApiError)} callback
  # @return {Nexus} this
  _refreshRtc: (rtcStat, callback) ->
    [hostId, inout] = rtcStat.name.split('|', 2)
    unless @_rtc[hostId]
      rtc = @_initRtc hostId
      rtc.answerHost hostId, @_hostId
      
    rtcData = @_rtcData[hostId]
    rtc = @_rtc[hostId]

    @dropboxChrome.client (client) =>
      client.readFile rtcStat.path, (error, string, stat) =>
        if error
          callback error
        else
          try
            rtcJson = JSON.parse string
          catch jsonError
            callback jsonError
            return
          @_rtcVersionTags[hostId] = stat.versionTag
          for [messageId, data] in rtcJson.sync
            if messageId <= rtcData.lastInId
              continue
            rtc.onSyncData data
            rtcData.lastInId = messageId
          callback null
    @

  # @param {String} peerHostId
  # @return {RTC}
  _initRtc: (peerHostId) ->
    rtc = new Rtc @

    @_rtc[peerHostId] = rtc
    @_rtcData[peerHostId] = lastInId: 0, lastOutId: 0, sync: []
    @_rtcWrite[peerHostId] = false
    @_rtcVersionTags[peerHostId] = null
    @_rtcVideo[peerHostId] = null

    rtc.onRemoteVideo.addListener (video) =>
      @_rtcVideo[peerHostId] = video
      @onRtc.dispatch peerHostId
    rtc


  # Maximum number of simultaneous Dropbox file reads.
  dropboxReadLimit: 2

  # Number of milliseconds to wait between two polling operations.
  pollingCooldownMs: 1000

  # Number of milliseconds to wait for coalescing RTC data writes.
  writeCoalesceMs: 500

window.Nexus = Nexus
