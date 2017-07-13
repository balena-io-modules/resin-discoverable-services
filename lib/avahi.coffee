EventEmitter = require('events').EventEmitter
Promise = require('bluebird')
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
		dbus.systemBus()
	.disposer (bus) ->
		bus?.connection?.end()

getAvahiServer = (bus) ->
	service = bus.getService(AVAHI_SERVICE_NAME)
	Promise.fromCallback (callback) ->
		service.getInterface('/', 'org.freedesktop.Avahi.Server', callback)

queryServices = (bus, avahiServer, identifier) ->
	serviceQueryPath = null
	unknownMessages = []

	emitter = new EventEmitter()
	emitIfRelevant = (msg) ->
		if msg.path == serviceQueryPath
			emitter.emit(msg.member, msg.body)

	bus.connection.on 'message', (msg) ->
		# Until we know our query's path, collect messages
		if not serviceQueryPath?
			unknownMessages.push(msg)
		# Once we know our query's path, raise events as relevant
		else emitIfRelevant(msg)

	Promise.fromCallback (callback) ->
		avahiServer.ServiceBrowserNew(IF_UNSPEC, PROTO_UNSPEC, identifier, 'local', 0, callback)
	.then (path) ->
		serviceQueryPath = path
		# Race condition! Handle any messages that would have matched this, but arrived too early
		unknownMessages.forEach(emitIfRelevant)
		unknownMessages = []
	.return(emitter)

findAvailableServices = (bus, avahiServer, { type, protocol, subtypes }, timeout = 2000) ->
	identifier = "_#{type}._#{protocol}"

	queryServices(bus, avahiServer, identifier)
	.then (serviceQuery) ->
		new Promise (resolve, reject) ->
			console.log('Listening for services...')

			services = []
			serviceQuery.on NEW_SIGNAL, (message) ->
				console.log('new item:', message)

			serviceQuery.on DONE_SIGNAL, (message) ->
				console.log('done')
				resolve(services)

			serviceQuery.on FAIL_SIGNAL, (message) ->
				console.log('error')
				reject(new Error(message))

			# If we run out of time, just return whatever we have so far
			setTimeout ->
				resolve(services)
			, timeout

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
