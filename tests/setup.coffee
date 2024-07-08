_ = require('lodash')
Promise = require('bluebird')
mkdirp = Promise.promisify(require('mkdirp'))
rmdir = Promise.promisify(require('rmdir'))
fs = Promise.promisifyAll(require('fs'))

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
