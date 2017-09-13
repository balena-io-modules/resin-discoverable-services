Promise = require('bluebird')
dns = require('dns')
dnsSd = require('./dns-sd')

# Apple's full docs for browsing with the Bonjour SDK (in C) are here:
# https://developer.apple.com/library/content/documentation/Networking/Conceptual/dns_discovery_api/Articles/browse.html#//apple_ref/doc/uid/TP40002486-SW1

exports.browse = ->
	flags = 0
	interfaceIndex = 0
	serviceType = '_ssh._tcp'
	domain = null

	dnsSd.browseServices(flags, interfaceIndex, serviceType, domain, 500)
	.map ({ interfaceIndex, serviceName, serviceType, domain }) ->
		dnsSd.resolveService(flags, interfaceIndex, serviceName, serviceType, domain)
		.then ([ flags, interfaceIndex, errorCode, domain, hostname, port, txtRecord ]) ->
			dnsLookup(hostname)
			.then ([ ipAddress, ipFamily ]) ->
				return { domain, hostname, port, ipAddress, ipFamily }

dnsLookup = (hostname) ->
	Promise.fromCallback (callback) ->
		dns.lookup(hostname, {}, callback)
	, { multiArgs: true }

exports.isAvailable = dnsSd.isAvailable
