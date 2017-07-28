Promise = require('bluebird')
_ = require('lodash')
bonjour = require('bonjour')

requiredBackend = process.env.BACKEND || 'native'

backendAvailability = {}
exports.checkBackendAvailability = (backends) ->
	if not _.includes(Object.keys(backends), requiredBackend)
		throw new Error('Unknown $BACKEND: ' + requiredBackend)

	_.forEach backends, (getBackend, name) ->
		Promise.using getBackend(), (backend) ->
			backendAvailability[name] = backend.isAvailable()

# Equivalent to mocha's `it`, but fails immediately if the required backend isn't available.
exports.givenBackendIt = (backendName, testName, body) ->
	it testName, ->
		backendAvailability[backendName].then (isAvailable) =>
			if isAvailable
				body.apply(this)
			else if backendName == requiredBackend
				throw new Error("#{backendName} tests required, but that backend is not available")
			else
				this.skip()

bonjourInstance = null
exports.publishService = (service) ->
	bonjourInstance ||= bonjour()
	bonjourInstance.publish(service)

exports.unpublishAllServices = ->
	return if not bonjourInstance?
	bonjourInstance.unpublishAll()
	bonjourInstance.destroy()
	bonjourInstance = null
