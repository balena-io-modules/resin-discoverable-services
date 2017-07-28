Promise = require('bluebird')
bonjour = require('bonjour')

class NativeServiceBrowser
	constructor: (@timeout) ->
		@findInstance = bonjour()

	find: (type, protocol, subtypes = []) ->
		# Perform the bonjour service lookup and return any results after the timeout period
		new Promise (resolve) =>
			foundServices = []
			browser = @findInstance.find
				type: type
				subtypes: subtypes
				protocol: protocol
			, (service) ->
				foundServices.push(service)

			setTimeout( ->
				browser.stop()
				resolve(foundServices)
			, @timeout)

	isAvailable: ->
		Promise.resolve(true)

	destroy: ->
		@findInstance.destroy()

module.exports = (timeout) ->
	Promise.resolve(new NativeServiceBrowser(timeout))
	.disposer (serviceBrowser) ->
		serviceBrowser.destroy()
