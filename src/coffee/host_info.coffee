class HostInfo
  # @param {Object<String, Object>} infoJson
  # @param {?Dropbox.Stat} infoStat
  # @param {?Dropbox.Stat} hostDirStat
  # @return {HostInfo}
  @parse: (infoJson, infoStat, hostDirStat) ->
    hostInfo = new HostInfo infoJson
    hostInfo.setInfoStat(infoStat).setDirStat hostDirStat
  
  # @property {String}
  id: null

  # @property {String}
  name: null
  
  # @property {String}
  userAgent: null

  # @property {String} the Dropbox version tag of the host info file 
  versionTag: null

  # @property {String} the Dropbox version tag of the host's directory
  dirVersionTag: null

  # @param {String} newUserAgent
  # @return {HostInfo} this
  setUserAgent: (newUserAgent) ->
    @_json = null
    @userAgent = newUserAgent
    @

  # @param {?Dropbox.Stat} infoStat
  # @return {HostInfo} this
  setInfoStat: (stat) ->
    if stat
      @versionTag = stat.versionTag
    @

  # @param {?Dropbox.Stat} hostDirStat
  # @return {HostInfo} this
  setDirStat: (hostDirStat) ->
    if hostDirStat
      @dirVersionTag = hostDirStat.versionTag
    @

  # @return {Object}
  json: ->
    @_json or= id: @id, name: @name, userAgent: @userAgent

  # @return {String}
  @randomId: ->
    Date.now().toString(36) + '_' + Math.random().toString(36).substring(2)

  # @param {?Object<String, Object>} infoJson
  constructor: (infoJson) ->
    @id = infoJson.id
    @name = infoJson.name
    @userAgent = infoJson.userAgent
    @versionTag = null
    @dirVersionTag = null
    @_json = null

window.HostInfo = HostInfo
