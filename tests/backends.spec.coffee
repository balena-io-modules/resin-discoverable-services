Promise = require('bluebird')
_ = require('lodash')
{ expect } = require('mochainon').chai

nativeBackend = require('../lib/backends/native')
avahiBackend = require('../lib/backends/avahi')

{ publishServices, unpublishServices, setRegistryPath } = require('../lib/discoverable')
{ checkBackendAvailability, givenBackendIt, givenServiceRegistry, testServicePath } = require('./setup')

backends =
	avahi: avahiBackend
	native: nativeBackend

checkBackendAvailability(backends)
_.forEach backends, ({ get: getBackend, isAvailable }, backendName) ->
	it = (testName, body) ->
		givenBackendIt(backendName, testName, body)

	describe "#{backendName} discovery backend", ->
		this.timeout(10000)

		givenServiceRegistry [
			{
				service: '._mockservice._tcp',
				opts: { name: 'Normal Service', port: 80, type: 'mockservice', subtypes: [ ], protocol: 'tcp' }
			},
			{
				service: '_test._sub._mockservice._tcp',
				opts: { name: 'Special Service', port: 8080, type: 'mockservice', subtypes: [ 'test' ], protocol: 'tcp' }
			}
		]

		it "says #{backendName} is available", ->
			expect(isAvailable()).to.eventually.equal(true)

		describe '.find', ->

			before ->
				setRegistryPath(testServicePath)
				publishServices [
					{ name: 'Normal Service', port: 80, identifier: '_mockservice._tcp' }
					{ name: 'Special Service', port: 8080, identifier: '_test._sub._mockservice._tcp' }
				]

			after ->
				unpublishServices()

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

					expect(specialService.name).to.equal('Special Service')
					expect(specialService.fqdn).to.equal('Special Service._mockservice._tcp.local')
					expect(specialService.protocol).to.equal('tcp')
					expect(specialService.referer.family).to.equal('IPv4')

			it 'can find a published service by subtype', ->
				Promise.using getBackend(), (backend) ->
					backend.find('mockservice', 'tcp', ['test'])
				.then (results) ->
					expect(results.length).to.equal(1)
					specialService = results[0]

					expect(specialService.name).to.equal('Special Service')
					expect(specialService.port).to.equal(8080)
					expect(specialService.fqdn).to.equal('Special Service._mockservice._tcp.local')
					expect(specialService.protocol).to.equal('tcp')
					expect(specialService.referer.family).to.equal('IPv4')
					expect(specialService.subtypes).to.deep.equal([ 'test' ])
