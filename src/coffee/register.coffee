class RegisterView
  constructor: (@root) ->
    @$root = $ @root
    @$hostNameField = $ '#host-name', @$root
    @$submitButton = $ '#registration-button', @$root
    @$cancelButton = $ '#cancel-button', @$root
    @$submitForm = $ '#registration-form', @$root
    @$submitForm.on 'submit', (event) => @onSubmit event

  onSubmit: (event) ->
    event.preventDefault()
    @$submitButton.attr 'disabled', true
    @$cancelButton.attr 'disabled', true
    hostName = @$hostNameField.val()
    chrome.runtime.getBackgroundPage (page) ->
      page.controller.registerHost hostName, ->
        window.close()

  onCancel: (event) ->
    window.close()

$ ->
  window.view = new RegisterView document.body
