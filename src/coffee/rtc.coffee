# Controller for one RTC connection.
class Rtc
  # @param {Nexus} nexus
  # @param {HostInfo} hostInfo
  constructor: (@nexus) ->
    @onRemoteVideo = new Dropbox.EventSource

    @supported = @computeSupported()
    @avReset()
    @rtcReset()

    @rtcAddStreamHandler = (event) => @onRtcAddStream event
    @iceCandidateHandler = (event) => @onIceCandidate event
    @iceChangeHandler = (event) => @onIceChange event
    @rtcNegotiationHandler = (event) => @onRtcNegotiationNeeded event
    @rtcOpenHandler = (event) => @onRtcOpen event
    @rtcRemoveStreamHandler = (event) => @onRtcRemoveStream event
    @rtcChangeHandler = (event) => @onRtcChange event

    @rtcOfferSuccessHandler = (sessDescription) =>
      @onRtcOfferCreate sessDescription
    @rtcAnswerSuccessHandler = (sessDescription) =>
      @onRtcAnswerCreate sessDescription
    @rtcLocalDescriptionSuccessHandler = => @onRtcLocalDescriptionSuccess()
    @rtcRemoteDescriptionSuccessHandler = => @onRtcRemoteDescriptionSuccess()
    @rtcErrorHandler = (errorText) => @onRtcError errorText

  # @property {Dropbox.EventSource<video stream>}
  onRemoteVideo: null

  # Called when the user clicks on the video button for a host.
  #
  # @param {String} calledHostId
  # @param {String} hostId
  callHost: (calledHostId, hostId) ->
    return if @calling or @answering

    @calling = true
    @callerHostId = hostId
    @calleeHostId = calledHostId
    @rtcConnect()

  # Called when the user clicks on the close video button for a host.
  closeCall: ->
    @rtcReset()
    @avReset()
    # TODO(pwnall): send hangup

  # Called when a video request is received.
  #
  # @param {String} callerHostId
  # @param {String} hostId
  answerHost: (callerHostId, hostId) ->
    return if @calling or @answering

    @answering = true
    @callerHostId = callerHostId
    @calleeHostId = hostId
    @rtcConnect()
    @avInput()

  # @return {String}
  peerDataFile: ->
    if @calling
      "#{@calleeHostId}/rtc/#{@callerHostId}|i.json"
    else
      "#{@callerHostId}/rtc/#{@calleeHostId}|o.json"

  # @return {String}
  peerHostId: ->
    if @calling
      @calleeHostId
    else
      @callerHostId

  # Prompts the user for permission to use the A/V inputs.
  avInput: ->
    @log 'avInput called'
    media = { video: true, audio: false }
    callback = (stream) => @onAvInputStream stream
    if navigator.getUserMedia
      navigator.getUserMedia media, callback
    if navigator.webkitGetUserMedia
      navigator.webkitGetUserMedia media, callback
    if navigator.mozGetUserMedia
      navigator.mozGetUserMedia media, callback

  # Called when the user's video input is provided to the application.
  onAvInputStream: (stream) ->
    @log ['onAvInputStream', stream]
    if @calling
      throw new Error 'Calling side should not use video'
      return
    else if @answering
      @localStream = stream
      @rtc.addStream @localStream
    else
      @rtcReset()
      @avReset()

  # Called when RTC control information is received.
  #
  # @param {Object} data argument passed to Nexus#sendSync
  onSyncData: (data) ->
    @log ['onSyncData', data]
    switch data.type
      when 'rtc-description'
        if data.description
          description = new RTCSessionDescription data.description
          @rtc.setRemoteDescription description,
              @rtcRemoteDescriptionSuccessHandler, @rtcErrorHandler
      when 'rtc-ice'
        if data.candidate
          candidate = new RTCIceCandidate data.candidate
          @rtc.addIceCandidate candidate

  # Re-initializes the RTC state after an error occurs.
  rtcReset: ->
    if @rtc
      @rtc.onaddstream = null
      @rtc.onicecandidate = null
      @rtc.onincechange = null
      @rtc.onnegotiationneeded = null
      @rtc.onopen = null
      @rtc.onremovestream = null
      @rtc.onstatechange = null
      @rtc.close()
      @rtc = null

  # Re-initializes the A/V state after an error occurs.
  avReset: ->
    @onRemoteVideo.dispatch null
    if @localStream
      @localStream.stop() if @localStream.stop
      @localStream = null
    if @remoteStream
      @remoteStream.stop() if @remoteStream.stop
      @remoteStream = null

    @calling = false
    @answering = false
    @callerHostId = null
    @calleeHostId = null

  # Creates a RTCPeerConnection and kicks off the ICE process.
  rtcConnect: ->
    unless @rtc = @rtcConnection()
      @avReset()
      @rtcReset()
      return

    @log ['rtcConnect', @rtc]
    try
      if @calling
        @rtc.createDataChannel 'i', reliable: false
      else
        @rtc.createDataChannel 'o', reliable: false
    catch rtcError
      @log ['rtcDataChannelError', rtcError]

  # Creates an RTCPeerConnection.
  rtcConnection: ->
    config = Rtc.rtcConfig()
    if window.RTCPeerConnection
      rtc = new RTCPeerConnection(config)
    else if window.webkitRTCPeerConnection
      rtc = new webkitRTCPeerConnection(config)
    else if window.mozRTCPeerConnection
      rtc = new mozRTCPeerConnection(config)
    else
      return null

    rtc.onaddstream = @rtcAddStreamHandler
    rtc.onicecandidate = @iceCandidateHandler
    rtc.onincechange = @iceChangeHandler
    rtc.onnegotiationneeded = @rtcNegotiationHandler
    rtc.onopen = @rtcOpenHandler
    rtc.onremovestream = @rtcRemoveStreamHandler
    rtc.onstatechange = @rtcChangeHandler
    rtc

  # Called when the remote side added a stream to the connection.
  onRtcAddStream: (event) ->
    @log ['addStream', event]
    if @remoteStream
      @remoteStream.stop() if @remoteStream.stop
    @remoteStream = event.stream
    @onRemoteVideo.dispatch @remoteStream

  # Called when the remote side removed a stream from the connection.
  onRtcRemoveStream: (event) ->
    @log ['removeStream', event]
    @onRemoteVideo.dispatch null
    @rtcReset()

  # Called when ICE has a candidate-something. (incomplete spec)
  onIceCandidate: (event) ->
    @nexus.sendRtcSync @, type: 'rtc-ice', candidate: event.candidate

  # Called when the ICE agent makes some progress. (incomplete spec)
  onIceChange: (event) ->
    @log ['iceChange', event]

  # Called when network changes require an ICE re-negotiation.
  onRtcNegotiationNeeded: (event) ->
    @log ['rtcNegotiationNeeded', event]
    if @calling
      @rtc.createOffer @rtcOfferSuccessHandler, @rtcErrorHandler

  # Called when something opens. (incomplete spec)
  onRtcOpen: (event) ->
    @log ['rtcOpen', event]

  # Called when the RTC state changes.
  onRtcChange: (event) ->
    @log ['rtcChange', event]

  # Called when RTCPeerConnection.createOffer succeeds.
  onRtcOfferCreate: (sessDescription) ->
    @rtc.setLocalDescription sessDescription,
        @rtcLocalDescriptionSuccessHandler, @rtcErrorHandler
    @nexus.sendRtcSync @, type: 'rtc-description', description: sessDescription

  # Called when RTCPeerConnection.createAnswer succeeds.
  onRtcAnswerCreate: (sessDescription) ->
    @rtc.setLocalDescription sessDescription,
        @rtcLocalDescriptionSuccessHandler, @rtcErrorHandler
    @nexus.sendRtcSync @, type: 'rtc-description', description: sessDescription

  # Called when RTCPeerConnection.setLocalDescription succeeds.
  onRtcLocalDescriptionSuccess: ->
    @log ['rtcLocalDescripionSuccess']

  # Called when RTCPeerConnection.setRemoteDescription succeeds.
  onRtcRemoteDescriptionSuccess: ->
    @log ['rtRemoteDescripionSuccess']
    if @answering
      @rtc.createAnswer @rtcAnswerSuccessHandler, @rtcErrorHandler

  # Called when a step in the RTC process fails.
  onRtcError: (errorText) ->
    # TODO(pwnall): report error
    @log ['rtcError', errorText]
    @onRemoteVideo.dispatch null
    @rtcReset()

  # Checks for getUserMedia and RTCPeerConnection support.
  computeSupported: ->
    @isRtcPeerConnectionSupported() && @isUserMediaSupported()

  isRtcPeerConnectionSupported: ->
    # NOTE: this method is overly complex, to match rtcConnection
    if window.RTCPeerConnection
      return true
    else if window.webkitRTCPeerConnection
      return true
    else if window.mozRTCPeerConnection
      return true
    else
      return false

  isUserMediaSupported: ->
    # NOTE: the method is overly complex, to match avInput
    if navigator.getUserMedia
      return true
    if navigator.webkitGetUserMedia
      return true
    if navigator.mozGetUserMedia
      return true
    false

  # Logs progress for the purpose of debugging.
  log: (data) ->
    if console and console.log
      console.log data

  # RTCPeerConnection configuration.
  @rtcConfig: ->
    iceServers: ({ url: "stun:#{url}" } for url in @stunServers())

  # Array of STUN servers that can be used by WebRTC.
  @stunServers: ->
    [
      "stun.l.google.com:19302",
      "stun1.l.google.com:19302",
      "stun2.l.google.com:19302",
      "stun3.l.google.com:19302",
      "stun4.l.google.com:19302",
      "stun01.sipphone.com",
      "stun.ekiga.net",
      "stun.fwdnet.net",
      "stun.ideasip.com",
      "stun.iptel.org",
      "stun.rixtelecom.se",
      "stun.schlund.de",
      "stunserver.org",
      "stun.softjoys.com",
      "stun.voiparound.com",
      "stun.voipbuster.com",
      "stun.voipstunt.com",
      "stun.voxgratia.org",
      "stun.xten.com",
    ]

window.Rtc = Rtc
