EventEmitter = require('events').EventEmitter
Promise = require('bluebird')
_ = require('lodash')
childProcess = require('child_process')

try
	# This will fail (silently) on non-Linux platforms
	dbus = require('dbus-native')

AVAHI_SERVICE_NAME = 'org.freedesktop.Avahi'

IF_UNSPEC = -1
PROTO_UNSPEC = -1
SIGNAL_MSG_TYPE = 4

NEW_SIGNAL = 'ItemNew'
DONE_SIGNAL = 'AllForNow'
FAIL_SIGNAL = 'Failure'

# Returns a Bluebird disposer: use with .using(getDbus(), (bus) -> ...)
# This ensures it's always closed, and doesn't stop the process ending
getDbus = ->
	Promise.try ->
		bus = dbus.systemBus()
		# Stop any connection errors killing the process
		bus.connection.on('error', ->)
		return bus
	.disposer (bus) ->
		bus?.connection?.end()

getAvahiServer = (bus) ->
	service = bus.getService(AVAHI_SERVICE_NAME)
	Promise.fromCallback (callback) ->
		service.getInterface('/', 'org.freedesktop.Avahi.Server', callback)
	.timeout(500)

queryServices = (bus, avahiServer, typeIdentifier) ->
	serviceBrowserPath = null
	unknownMessages = []

	emitter = new EventEmitter()
	emitIfRelevant = (msg) ->
		if msg.path == serviceBrowserPath
			emitter.emit(msg.member, msg.body)

	bus.connection.on 'message', (msg) ->
		console.log('got message', msg)
		return if msg.type != SIGNAL_MSG_TYPE

		# Until we know our query's path, collect messages
		if not serviceBrowserPath?
			unknownMessages.push(msg)
		# Once we know our query's path, raise events as relevant
		else emitIfRelevant(msg)

	Promise.fromCallback (callback) ->
		avahiServer.ServiceBrowserNew(IF_UNSPEC, PROTO_UNSPEC, typeIdentifier, 'local', 0, callback)
	.then (path) ->
		serviceBrowserPath = path
		# Race condition! Handle any messages that would have matched this, but arrived too early
		unknownMessages.forEach(emitIfRelevant)
		unknownMessages = []
	.return(emitter)
	.disposer ->
		if serviceBrowserPath
			Promise.fromCallback (callback) ->
				# Free the service browser
				bus.invoke
					path: serviceBrowserPath
					destination: 'org.freedesktop.Avahi'
					interface: 'org.freedesktop.Avahi.ServiceBrowser'
					member: 'Free'
				, callback

buildFullType = (type, protocol, subtype) ->
	if subtype?
		"_#{subtype}._sub._#{type}._#{protocol}"
	else
		"_#{type}._#{protocol}"

findAvailableServices = (bus, avahiServer, { type, protocol, subtype }, timeout = 1000) ->
	avahiBrowse = childProcess.spawn('avahi-browse', ['--all', '--resolve', '--terminate'])
	avahiBrowse.stdout.pipe(process.stdout)
	avahiBrowse.stderr.pipe(process.stderr)

	fullType = buildFullType(type, protocol, subtype)

	Promise.using queryServices(bus, avahiServer, fullType), (serviceQuery) ->
		new Promise (resolve, reject) ->
			services = []
			serviceQuery.on NEW_SIGNAL, (service) ->
				services.push(service)

			serviceQuery.on DONE_SIGNAL, (message) ->
				resolve(services)

			serviceQuery.on FAIL_SIGNAL, (message) ->
				reject(new Error(message))

			# If we run out of time, just return whatever we have so far
			setTimeout ->
				resolve(services)
			, timeout
	.delay(5000)
	.then (services) ->
		console.log('got services', services)
		Promise.map services, ([ inf, protocol, name, type, domain ]) ->
			Promise.fromCallback (callback) ->
				avahiServer.ResolveService(inf, protocol, name, type, domain, PROTO_UNSPEC, 0, callback)
			, { multiArgs: true }
			.catch (err) ->
				console.warn("Failed to resolve #{type}.#{domain}", err)
				return null # If services can fail to resolve: ignore them.
		.filter(_.identity)
		.map (result) ->
			formatAvahiService(subtype, result)

formatAvahiService = (subtype, [ inf, protocol, name, type, domain, host, aProtocol, address, port, txt, flags ]) ->
	fqdn: "#{name}.#{type}.#{domain}"
	port: port
	host: host
	protocol: if type.endsWith('_tcp') then 'tcp' else 'udp'
	subtypes: [ subtype ].filter(_.identity)
	referer:
		family: if protocol == 0 then 'IPv4' else 'IPv6'
		address: address

###
# @summary Detects whether a D-Bus Avahi connection is possible
# @function
# @public
#
# @description
# If the promise returned by this method resolves to true, other Avahi methods
# should work. If it doesn't, they definitely will not.
#
# @fulfil {boolean} - Is an Avahi connection possible
# @returns {Promise}
#
# @example
# avahi.isAvailable().then((canUseAvahi) => {
#   if (canUseAvahi) { ... }
# })
###
exports.isAvailable = ->
	# If we've failed to even load the module, then no, it's not available.
	if not dbus?
		return false

	Promise.using getDbus(), (bus) ->
		getAvahiServer(bus)
		.return(true)
	.catchReturn(false)

###
# @summary Find publicised services on the local network using Avahi
# @function
# @public
#
# @description
# Talks to Avahi over the system D-Bus, to query for local services
# and resolve their details.
#
# @fulfil {Service[]} - An array of service details
# @returns {Promise}
#
# @example
# avahi.find({ type: 'ssh', protocol: 'tcp', subtype: 'resin-device' ).then((services) => {
#   services.forEach((service) => ...)
# })
###
exports.find = ({ type, protocol, subtype }) ->
	Promise.using getDbus(), (bus) ->
		getAvahiServer(bus)
		.then (avahi) ->
			findAvailableServices(bus, avahi, { type, protocol, subtype })
