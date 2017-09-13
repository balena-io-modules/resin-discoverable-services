_ = require('lodash')
Promise = require('bluebird')

try
	# This will fail (silently) if DNS-SD bindings couldn't build
	dnsSd = require('bindings')('dns_sd_bindings.node')

# Starts watching a service ref for results to process
# Returns a stopWatching method, which must be called when
# the watched process is completed.
startWatching = (serviceRef) ->
	watcher = new dnsSd.SocketWatcher()
	watcher.callback = ->
		dnsSd.DNSServiceProcessResult(serviceRef)
	watcher.set(serviceRef.fd, true, false)
	watcher.start()

	return ->
		watcher.stop()
		dnsSd.DNSServiceRefDeallocate(serviceRef)

# Takes one of the many DNS-SD functions that are called with svcRef, flags,
# interfaceIndex and errorCode, and automatically handles serviceRef setup
# and watching, returning a stopWatching method.
wrapDnsSd = (dnsSdFunction, onResult, onError) ->
	return (args...) ->
		callback = (serviceRef, flags, interfaceIndex, errorCode) ->
			if errorCode != dnsSd.kDNSServiceErr_NoError
				onError(errorCode)
			else
				# Drop the 1st callback arg (the serviceRef)
				onResult([].slice.call(arguments, 1))

		serviceRef = new dnsSd.DNSServiceRef()
		dnsSdFunction.apply(this, [serviceRef].concat(args).concat(callback, null))
		return startWatching(serviceRef)

# Takes one of the many DNS-SD functions that are called with svcRef, flags,
# interfaceIndex and errorCode, and promisifies it, to automatically handle all
# serviceRef setup & teardown, and just resolve with the first returned result
# and watching, returning a stopWatching method.
promisifyDnsSd = (dnsSdFunction) ->
	(args...) ->
		stopWatching = ->
		return new Promise (resolve, reject) ->
			stopWatching = wrapDnsSd(dnsSdFunction, resolve, reject)(args...)
		.finally ->
			try
				stopWatching()

exports.isAvailable = ->
	if not dnsSd?
		return false

	try
		# Disable Avahi's "warning this is a compatibility layer" warning
		# See https://github.com/lathiat/avahi/blob/master/avahi-compat-libdns_sd/warn.c#L113-L117
		originalCompatWarningValue = process.env.AVAHI_COMPAT_NOWARN
		process.env.AVAHI_COMPAT_NOWARN = true

		serviceRef = new dnsSd.DNSServiceRef()
		dnsSd.DNSServiceBrowse(serviceRef, 0, 0, '_dns-sd-test._udp', null, (->), null)
		return true
	catch
		return false
	finally
		if serviceRef?
			try
				dnsSd.DNSServiceRefDeallocate(serviceRef)
		process.env.AVAHI_COMPAT_NOWARN = originalCompatWarningValue

if dnsSd?
	exports.dnsSdBinding = dnsSd

	# Browse services, collect results, and resolve a promise with them as an array on timeout
	exports.browseServices = (args..., timeout) ->
		stopWatching = ->
		return new Promise (resolve, reject) ->
			services = []
			stopWatching = wrapDnsSd(dnsSd.DNSServiceBrowse, (serviceChange) ->
				updateServices(services, serviceChange)
			, reject)(args...)

			setTimeout ->
				resolve(services)
			, timeout
		.finally ->
			try
				stopWatching()

	updateServices = (services, [ flags, interfaceIndex, errorCode, serviceName, serviceType, domain ]) ->
		service = { interfaceIndex, serviceName, serviceType, domain }
		if flags & dnsSd.kDNSServiceFlagsAdd
			services.push(service)
		else
			_.remove(services, service)

	exports.resolveService = promisifyDnsSd(dnsSd.DNSServiceResolve)
