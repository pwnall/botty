class BackgroundController
  # @param {Dropbox.Chrome} dropboxChrome
  constructor: (@dropboxChrome) ->
    chrome.browserAction.onClicked.addListener => @onBrowserAction()
    chrome.extension.onMessage.addListener => @onMessage
    chrome.runtime.onInstalled.addListener =>
      @onInstall()
      @onStart()
    chrome.runtime.onStartup.addListener => @onStart()

    @dropboxChrome.onClient.addListener (client) =>
      client.onAuthStateChange.addListener => @onRegistrationChange client
      client.onError.addListener (error) => @errorNotice error.toString()

    @locals = new Locals
    @nexus = new Nexus @dropboxChrome
    @nexus.onHostsChange.addListener =>
      chrome.runtime.sendMessage notice: 'hosts'
    @nexus.onRtc.addListener =>
      chrome.runtime.sendMessage notice: 'video'

  # Called by Chrome when the user installs the extension.
  onInstall: ->
    null

  # Called by Chrome when the user installs the extension or starts Chrome.
  onStart: ->
    @dropboxChrome.client (client) =>
      @onDropboxAuthChange client

  # Called by Chrome when the user clicks the browser action.
  onBrowserAction: ->
    @dropboxChrome.client (client) =>
      if client.isAuthenticated()
        @locals.hostId (hostId) =>
          if hostId
            @openManagement()
          else
            @openRegistration()
        return

      credentials = client.credentials()
      if credentials.authState
        # The user clicked our button while we're signing him/her into
        # Dropbox. Consider that the sign-up failed and try again. Most
        # likely, the user closed the Dropbox authorization tab.
        client.reset()

      @signIntoDropbox (error, client) =>
        if error
          @errorNotice error.toString()
          return
        @openRegistration()

  # Invalidates and discards the extension's Dropbox token.
  #
  # @private
  # This is called during the host's de-registration process.
  signOffDropbox: (callback) ->
    @dropboxChrome.signOut ->
      callback()

  # Obtains a Dropbox token.
  #
  # @private
  # This is called during the host registration process.
  signIntoDropbox: (callback) ->
    @dropboxChrome.client (client) ->
      client.authenticate (error) ->
        client.reset() if error
        callback()

  # Called when the host's registration state changes.
  onDropboxAuthChange: (client) ->
    @onRegistrationChange()

  # Called when the host's registration state changes.
  onRegistrationChange: ->
    @dropboxChrome.client (client) =>
      # Update the badge to reflect the current authentication state.
      if client.isAuthenticated()
        @locals.hostId (hostId) =>
          if hostId
            @nexus.setHostId hostId
            chrome.browserAction.setTitle title: 'Registered'
            chrome.browserAction.setBadgeText text: ''
          else
            chrome.browserAction.setTitle title: 'Click to register computer'
            chrome.browserAction.setBadgeText text: '?'
            chrome.browserAction.setBadgeBackgroundColor color: '#DF2020'
      else
        credentials = client.credentials()
        if credentials.authState
          chrome.browserAction.setTitle title: 'Signing in...'
          chrome.browserAction.setBadgeText text: '...'
          chrome.browserAction.setBadgeBackgroundColor color: '#DFBF20'
        else
          chrome.browserAction.setTitle title: 'Click to sign into Dropbox'
          chrome.browserAction.setBadgeText text: '?'
          chrome.browserAction.setBadgeBackgroundColor color: '#DF2020'

      chrome.extension.sendMessage notice: 'dropbox_auth'

  # Open the host registration page in a new tab.
  openRegistration: ->
    chrome.tabs.create url: 'html/register.html', active: false, pinned: false

  # Open the botnet management page in a new tab.
  openManagement: ->
    chrome.tabs.create url: 'html/manage.html', active: true, pinned: false

  # Called when the user wishes to add the host to their personal botnet.
  #
  # @param {String} hostName
  # @param {function()} callback
  registerHost: (hostName, callback) ->
    chrome.browserAction.setTitle title: 'Linking computer...'
    chrome.browserAction.setBadgeText text: '...'
    chrome.browserAction.setBadgeBackgroundColor color: '#DFBF20'

    hostInfo = new HostInfo id: HostInfo.randomId(), name: hostName
    @nexus.registerHost hostInfo, (error) =>
      if error
        @errorNotice error.toString()
        return
      @locals.saveRegistration hostInfo, =>
        @onRegistrationChange()
        @openManagement()
        callback()

  # Called when the user wishes to see the video stream from another host.
  requestVideo: (hostInfo) ->
    @nexus.callHost hostInfo

  # Shows a desktop notification informing the user that an error occurred.
  errorNotice: (errorText) ->
    webkitNotifications.createNotification 'images/icon48.png', 'Botty',
                                           errorText

dropboxChrome = new Dropbox.Chrome(
    key: 'UVGIJ5dpenA=|m4rL9ggAvA++3JN6DgZrSpfJaG1HBMRGtc4SnCwWMQ==',
    sandbox: true)
window.controller = new BackgroundController dropboxChrome
