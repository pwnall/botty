# Settings for the local instance.
class Locals
  constructor: ->
    @_items = null
    @_itemsCallbacks = null

  items: (callback) ->
    if @_items
      callback @_items
      return @

    if @_itemsCallbacks
      @_itemsCallbacks.push callback
      return @

    @_itemsCallbacks = [callback]
    chrome.storage.local.get 'settings', (storage) =>
      items = storage.settings || {}
      @addDefaults items
      @_items = items
      callbacks = @_itemsCallbacks
      @_itemsCallbacks = null
      for callback in callbacks
        callback @_items
    @

  setItems: (items, callback) ->
    @_items = items
    chrome.storage.local.set settings: items, =>
      callback() if callback
    @

  # @return {Locals} this
  saveRegistration: (hostInfo, callback) ->
    @items (items) =>
      items.hostId = hostInfo.id
      items.hostName = hostInfo.name
      @setItems items, =>
        callback()

  # @param {function(String)} callback
  # @return {Locals} this
  hostId: (callback) ->
    @items (items) ->
      callback items.hostId
    @

  addDefaults: (items) ->
    unless 'hostId' of items
      items.hostId = null
    unless 'hostName' of items
      items.hostName = null
    items

window.Locals = Locals
