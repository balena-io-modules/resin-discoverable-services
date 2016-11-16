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
os = require('os')
bonjour = require('bonjour')
_ = require('lodash')

# Set the memoize cache as a Map so we can clear it should the service
# registry change.
_.memoize.Cache = Map
registryPath = "#{__dirname}/../services"

# List of published services. The bonjourInstance is initially uncreated, and
# is created either by the publishing of a service, or by finding a service.
# It *must* be cleaned up and destroyed before exiting a process to ensure
# bound sockets are removed.
publishInstance = null

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
		fs.readdirAsync(parentPath)
		.then (paths) ->
			Promise.map paths, (path) ->
				fs.statAsync("#{parentPath}/#{path}")
				.then (stat) ->
					if stat.isDirectory()
						foundDirectories.push(path)
		.then ->
			if foundDirectories.length is 0
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
				if components.length is 3
					service = "_#{components[0]}._sub."
					components.shift()
				service += "_#{components[0]}._#{components[1]}"

				fs.readFileAsync("#{registryPath}#{path}/tags.json", { encoding: 'utf8' })
				.then (data) ->
					json = JSON.parse(data)
					if (not _.isArray(json))
						throw new Error()

					tags = json
				.catch (err) ->
					# If the tag file didn't exist, we silently fail.
					if err.code isnt 'ENOENT'
						throw new Error("tags.json for #{service} service defintion is incorrect")
				.then ->
					services.push({ service: service, tags: tags })
		.return(services)

# Set the services function as a memoized one.
registryServices = _.memoize(retrieveServices)

###
# @summary Determines if a service is valid.
# @function
# @private
###
findValidService = (serviceIdentifier, knownServices) ->
	_.find knownServices, ({ service, tags }) ->
		serviceIdentifier in [ service, tags... ]

###
# @summary Retrieves information for a given services string.
# @function
# @private
###
determineServiceInfo = (service) ->
	info = {}

	types = service.service.match(/^(_(.*)\._sub\.)?_(.*)\._(.*)$/)
	if not types[1]? and not types[2]?
		info.subtypes = []
	else
		info.subtypes = [ types[2] ]

	# We only try and find a service if the type is valid
	if types[3]? and types[4]?
		info.type = types[3]
		info.protocol = types[4]

	return info

###
# @summary Ensures valid network interfaces exist
# @function
# @private
###
hasValidInterfaces = ->
	# We can continue so long as we have one interface, and that interface is not loopback.
	_.some os.networkInterfaces(), (value) ->
		_.some(value, internal: false)

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
	if not path?
		path = "#{__dirname}/../services"

	if not _.isString(path)
		throw new Error('path parameter must be a path string')

	registryPath = path
	registryServices.cache.clear()

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
	registryServices()
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
# @param {Array} services - A string array of service identifiers or tags
# @param {Number} timeout - A timeout in milliseconds before results are returned. Defaults to 2000ms
# @param {Function} callback - callback (error, services)
#
# @example
# discoverableServices.findServices [ '_resin-device._sub._ssh._tcp' ], 5000, (error, services) ->
#	throw error if error?
#   # services is an array of every service that conformed to the specified search parameters
#   console.log(services)
###
exports.findServices = Promise.method (services, timeout, callback) ->
	# Check parameters.
	if not timeout?
		timeout = 2000
	else
		if not _.isNumber(timeout)
			throw new Error('timeout parameter must be a number value in milliseconds')

	if not _.isArray(services)
		throw new Error('services parameter must be an array of service name strings')

	if not hasValidInterfaces()
		throw new Error('At least one non-loopback interface must be present to bind to')

	# Perform the bonjour service lookup and return any results after the timeout period
	findInstance = bonjour()
	createBrowser = (serviceIdentifier, subtypes, type, protocol) ->
		new Promise (resolve) ->
			foundServices = []
			browser = findInstance.find { type: type, subtypes: subtypes, protocol: protocol }, (service) ->
				# Because we spin up a new search for each subtype, we don't
				# need to update records here. Any valid service is unique.
				service.service = serviceIdentifier
				foundServices.push(service)

			setTimeout( ->
				browser.stop()
				resolve(foundServices)
			, timeout)

	# Get the list of registered services.
	registryServices()
	.then (validServices) ->
		serviceBrowsers = []
		services.forEach (service) ->
			if (registeredService = findValidService(service, validServices))?
				serviceDetails = determineServiceInfo(registeredService)
				if serviceDetails.type? and serviceDetails.protocol?
					# Build a browser, set a timeout and resolve once that
					# timeout has finished
					serviceBrowsers.push(createBrowser	registeredService.service,
						serviceDetails.subtypes, serviceDetails.type, serviceDetails.protocol
					)

		Promise.all serviceBrowsers
		.then (services) ->
			services = _.flatten(services)
			_.remove(services, (entry) -> entry == null)
			return services
	.finally ->
		findInstance.destroy()
	.asCallback(callback)

###
# @summary Publishes all available services
# @function
# @public
#
# @description
# This function allows promise style if the callback is omitted.
# Note that it is vital that any published services are unpublished during exit of the process using `unpublishServices()`.
#
# @param {Array} services - An object array of service details. Each service object is comprised of:
# @param {String} services.identifier - A string of the service identifier or an associated tag
# @param {String} services.name - A string of the service name to advertise as
# @param {String} services.host - A specific hostname that will be used as the host (useful for proxying or psuedo-hosting). Defaults to current host name should none be given
# @param {Number} services.port - The port on which the service will be advertised
# @param {Array} services.addresses - Optional, and defaults to all host interfaces if not given. Othewise, an object with optional properties:
# @param {Array} services.addresses.ipv4 - An array of addresses in IPv4 dot-decimal notation, each as a string.
# @param {Array} services.addresses.ipv6 - An array of addresses in IPv6 hexadecimal notation, each as a string.
# @param {Function} callback - callback (error, services)
#
# @example
# discoverableServices.publishServices [ { identifier: '_resin-device._sub._ssh._tcp', name: 'Resin SSH', host: 'server1.local', port: 9999 } ], (error) ->
#	throw error if error?
#   # services is an array of service identifiers from the passed in list that were published (in the same format as passed)
#   console.log(services)
###
exports.publishServices = Promise.method (services, callback) ->
	if not _.isArray(services)
		throw new Error('services parameter must be an array of service objects')

	if not hasValidInterfaces()
		throw new Error('At least one non-loopback interface must be present to bind to')

	# Get the list of registered services.
	registryServices()
	.then (validServices) ->
		publishedList = []
		services.forEach (service) ->
			if service.identifier? and service.name? and (registeredService = findValidService(service.identifier, validServices))?
				serviceDetails = determineServiceInfo(registeredService)
				if serviceDetails.type? and serviceDetails.protocol? and service.port?
					if !publishInstance?
						publishInstance = bonjour()

					publishDetails =
						name: service.name
						port: service.port
						type: serviceDetails.type
						subtypes: serviceDetails.subtypes
						protocol: serviceDetails.protocol
						addresses: service.addresses
					if service.host? then publishDetails.host = service.host

					publishInstance.publish(publishDetails)
					publishedServices = true
					publishedList.push(service.identifier)

		return publishedList
	.asCallback(callback)

###
# @summary Unpublishes all available services
# @function
# @public
#
# @description
# This function allows promise style if the callback is omitted.
# This function must be called before process exit to ensure used sockets are destroyed.
#
# @example
# discoverableServices.unpublishServices()
###
exports.unpublishServices = (callback) ->
	return Promise.resolve().asCallback(callback) if not publishInstance?

	publishInstance.unpublishAll ->
		publishInstance.destroy()
		publishInstance = null
		return Promise.resolve().asCallback(callback)
