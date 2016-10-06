m = require('mochainon')
Promise = require('bluebird')
discoverableServices = require('../lib/discoverable')
mkdirp = Promise.promisify(require('mkdirp'))
rmdir = Promise.promisify(require('rmdir'))
fs = Promise.promisifyAll(require('fs'))
bonjour = require('bonjour')
_ = require('lodash')

expect = m.chai.expect
be = m.chai.be

describe 'Discoverable Services:', ->
	testServicePath = "#{__dirname}/test-services"
	dummyServices = [
		{
			path: "#{__dirname}/test-services/ssh/tcp",
			service: '_ssh._tcp',
			bonjourOpts: { name: 'Main SSH', port: 1234, type: 'ssh', protocol: 'tcp' }
		},
		{
			path: "#{__dirname}/test-services/private/ssh/tcp",
			service: '_private._sub._ssh._tcp',
			tags: [ 'our_private_ssh' ],
			bonjourOpts: { name: 'Private SSH', port: 2345, type: 'ssh', subtypes: [ 'private' ], protocol: 'tcp' }
		},
		{
			path: "#{__dirname}/test-services/noweb/gopher/udp",
			service: '_noweb._sub._gopher._udp'
			bonjourOpts: { name: 'Gopher', port: 3456, type: 'gopher', subtypes: [ 'noweb' ], protocol: 'udp' }
		}
	]

	before ->
		Promise.map dummyServices, (service) ->
			mkdirp(service.path)
			.then ->
				if service.tags?
					return fs.writeFileAsync("#{service.path}/tags.json", JSON.stringify(service.tags))

	after ->
		# Clean up, destroy the test-services directory
		rmdir(testServicePath)


	inspectEnumeratedServices = (services) ->
		expect(services.length).to.equal(dummyServices.length)
		services.forEach (service) ->
			dummyService = _.find dummyServices, (dummy) ->
				return if dummy.service == service.service then true else false

			expect(service.service).to.equal(dummyService.service)
			if dummyService.tags?
				expect(service.tags).to.deep.equal(dummyService.tags)

	describe '.setRegistryPath()', ->

		describe 'given invalid parameters', ->
			it 'should reject them', ->
				expect(-> discoverableServices.setRegistryPath([])).to.throw('path parameter must be a path string')


		describe 'using the default path', ->
			serviceName = '_resin-device._sub._ssh._tcp'
			tagNames = [ 'resin-ssh' ]

			it '.enumerateServices() should retrieve the resin-device.ssh service', (done) ->
				discoverableServices.enumerateServices (error, services) ->
					services.forEach (service) ->
						expect(service.service).to.equal(serviceName)
						expect(service.tags).to.deep.equal(tagNames)
					done()

				return

			it '.enumerateServices() should return a promise that resolves to the registered services', ->
				promise = discoverableServices.enumerateServices()
				expect(promise).to.eventually.deep.equal([ { service: serviceName, tags: tagNames } ])

		describe 'using a new registry path', ->
			before ->
				discoverableServices.setRegistryPath(testServicePath)

			it '.enumerateServices() should return a promise that enumerates all three valid services', ->
				discoverableServices.enumerateServices().return(inspectEnumeratedServices)

	describe '.enumerateServices()', ->

		describe 'using an invalid callback parameter', ->

			it '.enumerateServices() should throw an error', ->
				expect(-> discoverableServices.enumerateServices('spoon')).to.throw('callback parameter must be a function')

		describe 'using the test services registry path', ->

			it 'should return the registered services in a callback', (done) ->
				discoverableServices.enumerateServices (error, services) ->
					inspectEnumeratedServices(services)
					done()

				return

			it 'should return a promise that resolves to the registered services', ->
				discoverableServices.enumerateServices()
				.return (inspectEnumeratedServices)

	describe '.findServices()', ->
		bonjourInstance = bonjour()

		# Publish our dummy services up, using bonjour.
		before ->
			dummyServices.forEach (service) ->
				bonjourInstance.publish(service.bonjourOpts)

		# Stop the dummy services.
		after ->
			bonjourInstance.unpublishAll()
			bonjourInstance.destroy()

		describe 'using an invalid callback parameter', ->
			it '.enumerateServices() should throw an error with an service list', ->
				expect(-> discoverableServices.findServices('spoon')).to.throw('services parameter must be an array of service name strings')

			it '.enumerateServices() should throw an error with an invalid timeout', ->
				expect(-> discoverableServices.findServices([], 'spoon')).to.throw('timeout parameter must be a number value in milliseconds')

			it '.enumerateServices() should throw an error with an invalid callback', ->
				expect(-> discoverableServices.findServices([], 100, 'spoon')).to.throw('callback parameter must be a function')
		describe 'using a set of published services', ->
			this.timeout(10000)
			findService = (services, idName) ->
				return _.find services, (service) ->
					return if service.name == idName then true else false

			it 'should return only the gopher and private ssh service using default timeout as a promise', ->
				startTime = _.now()
				discoverableServices.findServices([ '_noweb._sub._gopher._udp', 'our_private_ssh' ])
				.then (services) ->
					expect(services.length).to.equal(2)
					_.find services, (service) ->
						elapsedTime = _.now() - startTime
						expect(elapsedTime).to.be.above(2000)
						expect(elapsedTime).to.be.below(7000)

						gopher = findService(services, 'Gopher')
						expect(gopher.service).to.equal('_noweb._sub._gopher._udp')
						expect(gopher.fqdn).to.equal('Gopher._gopher._udp.local')
						expect(gopher.subtypes).to.deep.equal(['noweb'])
						expect(gopher.port).to.equal(3456)
						expect(gopher.protocol).to.equal('udp')

						privateSsh = findService(services, 'Private SSH')
						expect(privateSsh.service).to.equal('_private._sub._ssh._tcp')
						expect(privateSsh.fqdn).to.equal('Private SSH._ssh._tcp.local')
						expect(privateSsh.subtypes).to.deep.equal(['private'])
						expect(privateSsh.port).to.equal(2345)
						expect(privateSsh.protocol).to.equal('tcp')

			it 'should return both main and private ssh services using default timeout via a callback', ->
				startTime = _.now()
				discoverableServices.findServices [ '_ssh._tcp' ], 6000, (error, services) ->
					expect(services.length).to.equal(2)
					_.find services, (service) ->
						elapsedTime = _.now() - startTime
						expect(elapsedTime).to.be.above(6000)
						expect(elapsedTime).to.be.below(7000)

						mainSsh = findService(services, 'Main SSH')
						expect(mainSsh.service).to.equal('_ssh._tcp')
						expect(mainSsh.fqdn).to.equal('Main SSH._ssh._tcp.local')
						expect(mainSsh.subtypes).to.deep.equal([])
						expect(mainSsh.port).to.equal(1234)
						expect(mainSsh.protocol).to.equal('tcp')

						# We didn't explicitly search for the private SSH services
						# so the subtype is empty and the service is just a vanilla
						# 'ssh' one.
						privateSsh = findService(services, 'Private SSH')
						expect(privateSsh.service).to.equal('_ssh._tcp')
						expect(privateSsh.fqdn).to.equal('Private SSH._ssh._tcp.local')
						expect(privateSsh.subtypes).to.deep.equal([])
						expect(privateSsh.port).to.equal(2345)
						expect(privateSsh.protocol).to.equal('tcp')
