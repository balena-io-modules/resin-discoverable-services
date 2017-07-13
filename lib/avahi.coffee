Promise = require('bluebird')
dbus = require('dbus-native')

# Returns a Bluebird disposer: use with .using(getDbus(), (bus) -> ...)
# This ensures it's always closed, and doesn't stop the process ending
getDbus = ->
	Promise.try ->
		# Can be replaced by dbus.systemBus() once https://github.com/sidorares/node-dbus/pull/151 is released
		# Should be first dbus-native release > 0.2.1
		dbus.createClient({
			busAddress: process.env.DBUS_SYSTEM_BUS_ADDRESS || 'unix:path=/var/run/dbus/system_bus_socket'
		})
	.disposer (bus) ->
		bus?.connection?.end()

getAvahiServer = (bus) ->
	service = bus.getService('org.freedesktop.Avahi')
	Promise.fromCallback (callback) ->
		service.getInterface('/', 'org.freedesktop.Avahi.Server', callback)

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
