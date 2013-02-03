class AvcView
  constructor: (@root) ->
    @$root = $ @root
    @$button = $ '#video-start', @$root
    @$button.click (event) => @onVideoStart event

  onVideoStart: (event) ->
    event.preventDefault()
    chrome.runtime.getBackgroundPage (page) ->
      page.Rtc.onAvcStart.dispatch window

$ ->
  window.view = new AvcView document.body
