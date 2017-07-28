_ = require('lodash')
Promise = require('bluebird')
mkdirp = Promise.promisify(require('mkdirp'))
rmdir = Promise.promisify(require('rmdir'))
fs = Promise.promisifyAll(require('fs'))

requiredBackend = process.env.BACKEND || 'native'

backendAvailability = {}
exports.checkBackendAvailability = (backends) ->
	if not _.includes(Object.keys(backends), requiredBackend)
		throw new Error('Unknown $BACKEND: ' + requiredBackend)

	_.forEach backends, ({ isAvailable }, name) ->
		backendAvailability[name] = isAvailable()

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

exports.testServicePath = "#{__dirname}/test-services"
exports.givenServiceRegistry = (testServices) ->
	before ->
		Promise.map testServices, (service) ->
			{ subtypes: [subtype], type, protocol } = service.opts

			if subtype
				path = "#{exports.testServicePath}/#{subtype}/#{type}/#{protocol}"
			else
				path = "#{exports.testServicePath}/#{type}/#{protocol}"

			mkdirp(path)
			.then ->
				if service.tags?
					return fs.writeFileAsync("#{path}/tags.json", JSON.stringify(service.tags))

	after ->
		rmdir(exports.testServicePath)
