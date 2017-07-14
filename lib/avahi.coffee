EventEmitter = require('events').EventEmitter
Promise = require('bluebird')
dbus = require('dbus-native')
_ = require('lodash')

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
		dbus.systemBus()
	.disposer (bus) ->
		bus?.connection?.end()

getAvahiServer = (bus) ->
	service = bus.getService(AVAHI_SERVICE_NAME)
	Promise.fromCallback (callback) ->
		service.getInterface('/', 'org.freedesktop.Avahi.Server', callback)

queryServices = (bus, avahiServer, typeIdentifier) ->
	serviceBrowserPath = null
	unknownMessages = []

	emitter = new EventEmitter()
	emitIfRelevant = (msg) ->
		if msg.path == serviceBrowserPath
			emitter.emit(msg.member, msg.body)

	bus.connection.on 'message', (msg) ->
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

formatAvahiService = ([ inf, protocol, name, type, domain, host, aProtocol, address, port, txt, flags ]) ->
	service: type
	fqdn: "#{name}.#{type}.#{domain}"
	port: port
	host: host
	protocol: if type.endsWith('_tcp') then 'tcp' else 'udp'
	subtypes: []
	referer:
		family: if protocol == 0 then 'IPv4' else 'IPv6'
		address: address


findAvailableServices = (bus, avahiServer, { type, protocol, subtypes }, timeout = 2000) ->
	Promise.using queryServices(bus, avahiServer, "_#{type}._#{protocol}"), (serviceQuery) ->
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
	.then (services) ->
		Promise.map services, ([ inf, protocol, name, type, domain ]) ->
			Promise.fromCallback (callback) ->
				avahiServer.ResolveService(inf, protocol, name, type, domain, PROTO_UNSPEC, 0, callback)
			, { multiArgs: true }
		.map(formatAvahiService)

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
	Promise.using getDbus(), (bus) ->
		getAvahiServer(bus)
		.return(true)
	.catchReturn(false)

exports.find = ({ type, protocol, subtypes = [] }) ->
	Promise.using getDbus(), (bus) ->
		getAvahiServer(bus)
		.then (avahi) ->
			findAvailableServices(bus, avahi, { type, protocol, subtypes })
		.then (services) ->
			console.log(services)
