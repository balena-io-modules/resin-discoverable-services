Promise = require('bluebird')
_ = require('lodash')
{ expect } = require('mochainon').chai

avahi = require('../lib/backends/avahi')
{ givenAvahiIt } = require('./setup')

{ publishService, unpublishAllServices } = require('./setup')

describe 'Avahi discovery backend', ->
	this.timeout(10000)

	givenAvahiIt 'says Avahi is available', ->
		expect(avahi.isAvailable()).to.eventually.equal(true)

	describe '.find', ->

		before ->
			publishService
				name: 'Normal Service', port: 80,
				type: 'mockservice', subtypes: [ ], protocol: 'tcp'

			publishService
				name: 'Special Test Service', port: 8080,
				type: 'mockservice', subtypes: [ 'test' ], protocol: 'tcp'

			Promise.delay(1000) # Add a little delay to make sure services are published

		after(unpublishAllServices)

		givenAvahiIt 'can find a published service', ->
			avahi.find('mockservice', 'tcp')
			.then (results) ->
				expect(results.length).to.equal(2)
				normalService = _.find(results, { port: 80 })

				expect(normalService.fqdn).to.equal('Normal Service._mockservice._tcp.local')
				expect(normalService.protocol).to.equal('tcp')
				expect(normalService.referer.family).to.equal('IPv4')

		givenAvahiIt 'returns a result for each subtype of the matching service', ->
			avahi.find('mockservice', 'tcp')
			.then (results) ->
				expect(results.length).to.equal(2)
				specialService = _.find(results, { port: 8080 })

				expect(specialService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
				expect(specialService.protocol).to.equal('tcp')
				expect(specialService.referer.family).to.equal('IPv4')

		givenAvahiIt 'can find a published service by subtype', ->
			avahi.find('mockservice', 'tcp', ['test'])
			.then (results) ->
				expect(results.length).to.equal(1)
				testService = results[0]

				expect(testService.port).to.equal(8080)
				expect(testService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
				expect(testService.protocol).to.equal('tcp')
				expect(testService.referer.family).to.equal('IPv4')
				expect(testService.subtypes).to.deep.equal([ 'test' ])
