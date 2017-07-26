_ = require('lodash')
{ expect } = require('mochainon').chai

avahi = require('../lib/backends/avahi')
{ givenAvahiIt } = require('./setup')

{ publishService, unpublishAllServices } = require('./setup')

# Seemingly very unused/unpopular service type, unlikely to exist on your local network
# Avahi rejects unknown types, and many other types (e.g. SSH) can be present in dev
MOCK_SERVICE_TYPE = 'writietalkie'

describe 'Avahi discovery backend', ->
	this.timeout(10000)

	givenAvahiIt 'says Avahi is available', ->
		expect(avahi.isAvailable()).to.eventually.equal(true)

	describe '.find', ->

		before ->
			publishService
				name: 'Normal Service', port: 80,
				type: MOCK_SERVICE_TYPE, subtypes: [ ], protocol: 'tcp'

			publishService
				name: 'Special Test Service', port: 8080,
				type: MOCK_SERVICE_TYPE, subtypes: [ 'test' ], protocol: 'tcp'

		after(unpublishAllServices)

		givenAvahiIt 'can find a published service', ->
			avahi.find({ type: MOCK_SERVICE_TYPE, protocol: 'tcp' })
			.then (results) ->
				expect(results.length).to.equal(2)
				normalService = _.find(results, { port: 80 })

				expect(normalService.fqdn).to.equal('Normal Service._mockservice._tcp.local')
				expect(normalService.protocol).to.equal('tcp')
				expect(normalService.referer.family).to.equal('IPv4')

		givenAvahiIt 'can find a published service by subtype', ->
			avahi.find({ type: MOCK_SERVICE_TYPE, protocol: 'tcp', subtype: 'test' })
			.then (results) ->
				expect(results.length).to.equal(1)
				testService = results[0]

				expect(testService.port).to.equal(8080)
				expect(testService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
				expect(testService.protocol).to.equal('tcp')
				expect(testService.referer.family).to.equal('IPv4')
				expect(testService.subtypes).to.deep.equal([ 'test' ])
