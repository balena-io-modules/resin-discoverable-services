Promise = require('bluebird')
dbus = require('dbus-native')

AVAHI_SERVICE_NAME = 'org.freedesktop.Avahi'

IF_UNSPEC = -1
PROTO_UNSPEC = -1

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

matchSignal = (bus, path, method) ->
	Promise.fromCallback (callback) ->
		bus.addMatch("type='signal',path='#{path}',member='#{method}'", callback)

onSignal = (bus, serviceBrowser, signal, callback) ->
	signalFullName = bus.mangle(serviceBrowser.name, 'org.freedesktop.Avahi.ServiceBrowser', signal)
	bus.signals.on signalFullName, (messageBody) ->
			callback(messageBody)

findAvailableServices = (bus, avahiServer, { type, protocol, subtypes }) ->
	identifier = "_#{type}._#{protocol}"

	Promise.fromCallback (callback) ->
		avahiServer.ServiceBrowserNew(IF_UNSPEC, PROTO_UNSPEC, identifier, 'local', 0, callback)
	.then (serviceBrowserPath) ->
		Promise.fromCallback (callback) ->
			bus.getObject(AVAHI_SERVICE_NAME, serviceBrowserPath, callback)
	.then (serviceBrowser) ->
		Promise.all [NEW_SIGNAL, DONE_SIGNAL, FAIL_SIGNAL].map (signalName) ->
			matchSignal(bus, serviceBrowser.name, signalName)
		.then ->
			new Promise (resolve, reject) ->
				services = []
				onSignal bus, serviceBrowser, NEW_SIGNAL, (message) ->
					console.log('new item:', message)

				onSignal bus, serviceBrowser, DONE_SIGNAL, (message) ->
					console.log('done')
					resolve(services)

				onSignal bus, serviceBrowser, FAIL_SIGNAL, (message) ->
					console.log('error')
					reject(new Error(message))

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
