try
	# This will fail (silently) if DNS-SD bindings couldn't build
	dnsSd = require('bindings')('dns_sd_bindings.node')

exports.isAvailable = ->
	return dnsSd?
