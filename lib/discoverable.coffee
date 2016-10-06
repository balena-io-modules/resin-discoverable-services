###
Copyright 2016 Resin.io

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
###

Promise = require('bluebird')
fs = Promise.promisifyAll(require('fs'))
bonjour = require('bonjour')
_ = require('lodash')

# Set the memoize cache as a Map so we can clear it should the service
# registry change.
_.memoize.Cache = Map
registryPath = "#{__dirname}/../services"

###
# @summary Scans the registry path hierarchy to determine service types.
# @function
# @private
###
retrieveServices = ->
	foundPaths = []
	scanDirectory = (parentPath, localPath) ->
		# Scan for directory names,
		foundDirectories = []
		return fs.readdirAsync(parentPath)
		.then (paths) ->
			Promise.map paths, (path) ->
				fs.statAsync("#{parentPath}/#{path}")
				.then (stat) ->
					if stat.isDirectory()
						foundDirectories.push(path)
		.then ->
			if foundDirectories.length == 0
				foundPaths.push(localPath)
			else
				# Prepend our path onto it
				Promise.map foundDirectories, (path) ->
					# Scan each of these
					scanDirectory("#{parentPath}/#{path}", "#{localPath}/#{path}")

	scanDirectory(registryPath, '')
	.then ->
		services = []

		# Only depths of 2 or 3 levels are valid (subtype/type/protocol).
		# Any incorrect depths are ignored, as we would prefer to retrieve the
		# services if at all possible
		Promise.map foundPaths, (path) ->
			components = _.split(path, '/')
			components.shift()

			# Ignore any non-valid service structure
			if (components.length >= 2 or components.length <= 3)
				service = ''
				tags = []
				if components.length == 3
					service = "_#{components[0]}._sub."
					components.shift()
				service += "_#{components[0]}._#{components[1]}"

				fs.readFileAsync("#{registryPath}#{path}/tags.json", { encoding: 'utf8' })
				.then (data) ->
					json = JSON.parse(data)
					if (!_.isArray(json))
						throw new Error()

					tags = json
				.catch (err) ->
					# If the tag file didn't exist, we silently fail.
					if (err.code != 'ENOENT')
						throw new Error("tags.json for #{service} service defintion is incorrect")
				.then ->
					services.push({ service: service, tags: tags })
		.return(services)

# Set the services function as a memoized one.
services = _.memoize(retrieveServices)

###
# @summary Sets the path which will be examined for service definitions.
# @function
# @public
#
# @description
# Should no parameter be passed, or this method not called, then the default
# path is the 'services' directory that exists within the module's directory
# hierarchy.
#
# @param {String} path - New path to use as the service registry.
#
# @example
# discoverableServices.setRegistryPath("/home/heds/discoverable_services")
###
exports.setRegistryPath = (path) ->
	if !path?
		path = "#{__dirname}/../services"

	if !_.isString(path)
		throw new Error('path parameter must be a path string')

	registryPath = path
	services.cache.clear()

###
# @summary Enumerates all currently registered services available for discovery.
# @function
# @public
#
# @description
# This function allows promise style if the callback is omitted.
#
# @param {Function} callback - callback (error, services)
#
# @example
# discoverableServices.enumerateServices (error, services) ->
#   throw error if error?
#   # services is an array of service objects holding type/subtype and any tagnames associated with them
#   console.log(services)
###
exports.enumerateServices = (callback) ->
	if callback? and !_.isFunction(callback)
		throw new Error('callback parameter must be a function')

	services()
	.asCallback(callback)

###
# @summary Listens for all locally published services, returning information on them after a period of time.
# @function
# @public
#
# @description
# This function allows promise style if the callback is omitted. Should the timeout value be missing
# then a default timeout of 2000ms is used.
#
# @param {Array} services - A string array of service names or tags
# @param {Number} timeout - A timeout in milliseconds before results are returned. Defaults to 2000ms
# @param {Function} callback - callback (error, services)
#
# @example
# discoverableServices.findServices([ '_resin-device._sub._ssh._tcp' ], 5000, (error, services) ->
#	throw error if error?
#   # services is an array of every service that conformed to the specified search parameters
#   console.log(services)
###
exports.findServices = (services, timeout, callback) ->
	# Check parameters.
	if !timeout?
		timeout = 2000
	else
		if !_.isNumber(timeout)
			throw new Error('timeout parameter must be a number value in milliseconds')

	if !_.isArray(services)
		throw new Error('services parameter must be an array of service name strings')

	if callback? and !_.isFunction(callback)
		throw new Error('callback parameter must be a function')

	# Perform the bonjour service lookup and return any results after the timeout period
	bonjourInstance = bonjour()
	createBrowser = (serviceName, subtypes, type, protocol) ->
		return new Promise (resolve) ->
			foundServices = []
			browser = bonjourInstance.find { type: type, subtypes: subtypes, protocol: protocol },
				(service) ->
					# Because we spin up a new search for each subtype, we don't
					# need to update records here. Any valid service is unique.
					service.service = serviceName
					foundServices.push(service)

			setTimeout( ->
				browser.stop()
				resolve(foundServices)
			, timeout)

	# Find only registered services
	findValidService = (serviceName, knownServices) ->
		return _.find knownServices, (service) ->
			if service.service == serviceName
				return true
			else
				return (_.indexOf(service.tags, serviceName) != -1)

			return false

	# Get the list of registered services.
	retrieveServices()
	.then (validServices) ->
		serviceBrowsers = []
		services.forEach (service) ->
			if (registeredService = findValidService(service, validServices))?
				types = registeredService.service.match(/^(_(.*)\._sub\.)?_(.*)\._(.*)$/)
				if types[1] == undefined and types[2] == undefined
					subtypes = []
				else
					subtypes = [ types[2] ]

				# We only try and find a service if the type is valid
				if types[3]? and types[4]?
					type = types[3]
					protocol = types[4]
					# Build a browser, set a timeout and resolve once that
					# timeout has finished
					serviceBrowsers.push(createBrowser(registeredService.service, subtypes, type, protocol))

		Promise.all serviceBrowsers
		.then (services) ->
			services = _.flatten(services)
			_.remove(services, (entry) -> entry == null)
			return services
	.finally ->
		bonjourInstance.destroy()
	.asCallback(callback)
