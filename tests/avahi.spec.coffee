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

		after(unpublishAllServices)

		givenAvahiIt 'can find a published service', ->
			avahi.find({ type: 'mockservice', protocol: 'tcp' })
			.then (results) ->
				expect(results.length).to.equal(2)
				normalService = _.find(results, { port: 80 })

				expect(normalService.fqdn).to.equal('Normal Service._mockservice._tcp.local')
				expect(normalService.service).to.equal('_mockservice._tcp')
				expect(normalService.protocol).to.equal('tcp')
				expect(normalService.referer.family).to.equal('IPv4')

		givenAvahiIt 'can find a published service by subtype', ->
			avahi.find({ type: 'mockservice', protocol: 'tcp', subtype: 'test' })
			.then (results) ->
				expect(results.length).to.equal(1)
				testService = results[0]

				expect(testService.port).to.equal(8080)
				expect(testService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
				expect(testService.service).to.equal('_test._sub._mockservice._tcp')
				expect(testService.protocol).to.equal('tcp')
				expect(testService.referer.family).to.equal('IPv4')
				expect(testService.subtypes).to.deep.equal([ 'test' ])