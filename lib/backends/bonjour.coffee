try
	# This will fail (silently) if DNS-SD bindings couldn't build
	dnsSd = require('bindings')('dns_sd_bindings.node')

# Apple's full docs for browsing with the Bonjour SDK (in C) are here:
# https://developer.apple.com/library/content/documentation/Networking/Conceptual/dns_discovery_api/Articles/browse.html#//apple_ref/doc/uid/TP40002486-SW1

exports.browse = ->
	serviceRef = new dnsSd.DNSServiceRef()

	flags = 0
	interfaceIndex = 0
	serviceType = '_ssh._tcp'
	domain = null
	callbackContext = null
	dnsSd.DNSServiceBrowse(serviceRef, flags, interfaceIndex, serviceType, domain, onServiceChange, callbackContext)
	stopWatching = startWatching(serviceRef)
	setTimeout(stopWatching, 30000)

startWatching = (serviceRef) ->
	watcher = new dnsSd.SocketWatcher()
	watcher.callback = ->
		dnsSd.DNSServiceProcessResult(serviceRef)
	watcher.set(serviceRef.fd, true, false)
	watcher.start()

	return ->
		watcher.stop()
		dnsSd.DNSServiceRefDeallocate(serviceRef)

onServiceChange = (sdRef, flags, interfaceIndex, errorCode, serviceName, serviceType, replyDomain, context) ->
	if not errorCode == dnsSd.kDNSServiceErr_NoError
		console.error("Error in Bonjour browsing, code: #{errorCode}")
		return

	if flags & dnsSd.kDNSServiceFlagsAdd
		onServiceFound(interfaceIndex, serviceName, serviceType, replyDomain)
	else
		onServiceLost(interfaceIndex, serviceName, serviceType, replyDomain)

onServiceFound = (interfaceIndex, serviceName, serviceType, replyDomain) ->
	console.log('found', arguments)

onServiceLost = (interfaceIndex, serviceName, serviceType, replyDomain) ->
	console.log('lost', arguments)

exports.isAvailable = ->
	if not dnsSd?
		return false

	try
		# Disable Avahi's "warning this is a compatibility layer" warning
		# See https://github.com/lathiat/avahi/blob/master/avahi-compat-libdns_sd/warn.c#L113-L117
		originalCompatWarningValue = process.env.AVAHI_COMPAT_NOWARN
		process.env.AVAHI_COMPAT_NOWARN = true

		serviceRef = new dnsSd.DNSServiceRef()
		dnsSd.DNSServiceBrowse(serviceRef, 0, 0, '_ssh._tcp', null, (->), null)
		return true
	catch
		return false
	finally
		if serviceRef?
			try
				dnsSd.DNSServiceRefDeallocate(serviceRef)
		process.env.AVAHI_COMPAT_NOWARN = originalCompatWarningValue
