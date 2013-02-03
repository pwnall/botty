class HostsView
  constructor: (@root) ->
    @$root = $ @root
    @$closeButton = $ '#close-window-button', @$root
    @$closeButton.click (event) => @onCloseClick event
    @$hostList = $ '#host-list', @$root
    @$videoList = $ '#video-list', @$root
    @hostTemplate = $('#host-template', @$root).text().trim()
    @videoTemplate = $('#video-template', @$root).text().trim()

    @hosts = []
    @$hostDoms = []
    @hostIndexes = {}

    chrome.runtime.onMessage.addListener (message) => @onMessage message

    @updateHostList()

  onVideoClick: (event, host) ->
    chrome.runtime.getBackgroundPage (page) ->
      page.controller.requestVideo host

  updateHostList: ->
    chrome.runtime.getBackgroundPage (page) =>
      page.controller.nexus.hosts (hostMap) =>
        hosts = []
        for own hostId, hostInfo of hostMap
          hosts.push hostInfo if hostInfo.name
        hosts.sort (a, b) ->
          a.name.localeCompare b.name
        @hosts = hosts
        @hostIndexes = {}
        @hostIndexes[hostInfo.id] = i for hostInfo, i in @hosts

        @renderHostList()
    @

  # Redraws the entire host list.
  renderHostList: ->
    @$hostList.empty()
    hostDoms = []
    for hostInfo in @hosts
      $hostDom = $ @hostTemplate
      @updateHostDom $hostDom, hostInfo
      @$hostList.append $hostDom
      @wireHostDom $hostDom, hostInfo
      hostDoms.push $hostDom
    @$hostDoms = hostDoms
    @

  # Sets up event listeners for the buttons in a host's view.
  wireHostDom: ($hostDom, hostInfo) ->
    $('.host-video-rtc', $hostDom).click (event) =>
      @onVideoClick event, hostInfo
    @

  # Updates the DOM for a host entry to reflect the host's current state.
  updateHostDom: ($hostDom, host) ->
    $('.host-name', $hostDom).text host.name

  updateVideoList: ->
    chrome.runtime.getBackgroundPage (page) =>
      page.controller.nexus.videos (videoMap) =>
        videos = []
        for own hostId, stream of videoMap
          if stream
            videos.push hostId: hostId, stream: stream
        videos.sort (a, b) ->
          a.hostId.localeCompare b.hostId
        @videos = hosts
        @videoIndexes = {}
        @videoIndexes[video.hostId] = i for video, i in @hosts

        @renderVideoList()
    @

  # Redraws the entire video stream list.
  renderVideoList: ->
    @$videoList.empty()
    videoDoms = []
    for video in @videos
      $videoDom = $ @videoTemplate
      @updateVideoDom $videoDom, video
      @$hostList.append $videoDom
      @wireHostDom $videoDom, video
      videoDoms.push $videoDom
    @$videoDoms = videoDoms
    @

  # Sets up event listeners for the buttons in a video view.
  wireVideoDom: ($videoDom, video) ->
    @

  # Updates the DOM for a host entry to reflect the video stream's state.
  updateVideoDom: ($videoDom, video) ->
    $('.video-host-name', $hostDom).text video.hostId
    $('video', $hostDom)[0].src = window.URL.createObjectUrl video.stream

  onMessage: (message) ->
    switch message.notice
      when 'hosts'
        @updateHostList()
      when 'video'
        @updateVideoList()

  onCloseClick: (event) ->
    window.close()

$ ->
  window.view = new HostsView document.body
