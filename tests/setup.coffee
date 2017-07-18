bonjour = require('bonjour')

avahi = require('../lib/backends/avahi')

backend = process.env.BACKEND || 'default'
if backend != 'default' and backend != 'avahi'
	throw new Error('Unknown $BACKEND: ' + backend)

# Equivalent to mocha's `it`, but fails immediately if Avahi isn't available.
# If `skipUnavailable` is truthy, just quietly skips tests instead.
avahiAvailabilityPromise = null
exports.givenAvahiIt = (name, body) ->
	it name, ->
		if not avahiAvailabilityPromise?
			avahiAvailabilityPromise = avahi.isAvailable()

		avahiAvailabilityPromise.then (isAvailable) =>
			if isAvailable
				body.apply(this)
			else if backend == 'avahi'
				throw new Error('Avahi tests required, but Avahi is not available')
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
