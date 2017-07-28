Promise = require('bluebird')
_ = require('lodash')
{ expect } = require('mochainon').chai

getNativeBackend = require('../lib/backends/native')
getAvahiBackend = require('../lib/backends/avahi')

{ checkBackendAvailability, givenBackendIt, publishService, unpublishAllServices } = require('./setup')

backends =
	avahi: -> getAvahiBackend(1000)
	native: -> getNativeBackend(1000)

checkBackendAvailability(backends)
_.forEach backends, (getBackend, backendName) ->
	it = (testName, body) ->
		givenBackendIt(backendName, testName, body)

	describe "#{backendName} discovery backend", ->
		this.timeout(10000)

		it "says #{backendName} is available", ->
			Promise.using getBackend(), (backend) ->
				expect(backend.isAvailable()).to.eventually.equal(true)

		describe '.find', ->

			before ->
				publishService
					name: 'Normal Service', port: 80,
					type: 'mockservice', subtypes: [ ], protocol: 'tcp'

				publishService
					name: 'Special Test Service', port: 8080,
					type: 'mockservice', subtypes: [ 'test' ], protocol: 'tcp'

				Promise.delay(500) # Add a little delay to make sure services are published

			after ->
				unpublishAllServices()
				Promise.delay(500)

			it 'can find a published service', ->
				Promise.using getBackend(), (backend) ->
					backend.find('mockservice', 'tcp')
				.then (results) ->
					expect(results.length).to.equal(2)
					normalService = _.find(results, { port: 80 })

					expect(normalService.name).to.equal('Normal Service')
					expect(normalService.fqdn).to.equal('Normal Service._mockservice._tcp.local')
					expect(normalService.protocol).to.equal('tcp')
					expect(normalService.referer.family).to.equal('IPv4')

			it 'returns a result for each subtype of the matching service', ->
				Promise.using getBackend(), (backend) ->
					backend.find('mockservice', 'tcp')
				.then (results) ->
					expect(results.length).to.equal(2)
					specialService = _.find(results, { port: 8080 })

					expect(specialService.name).to.equal('Special Test Service')
					expect(specialService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
					expect(specialService.protocol).to.equal('tcp')
					expect(specialService.referer.family).to.equal('IPv4')

			it 'can find a published service by subtype', ->
				Promise.using getBackend(), (backend) ->
					backend.find('mockservice', 'tcp', ['test'])
				.then (results) ->
					expect(results.length).to.equal(1)
					testService = results[0]

					expect(testService.name).to.equal('Special Test Service')
					expect(testService.port).to.equal(8080)
					expect(testService.fqdn).to.equal('Special Test Service._mockservice._tcp.local')
					expect(testService.protocol).to.equal('tcp')
					expect(testService.referer.family).to.equal('IPv4')
					expect(testService.subtypes).to.deep.equal([ 'test' ])
