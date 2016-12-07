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
			path: "#{__dirname}/test-services/first/ssh/tcp",
			service: '_first._sub._ssh._tcp',
			bonjourOpts: { name: 'First SSH', port: 1234, type: 'ssh', subtypes: [ 'first' ], protocol: 'tcp' }
		},
		{
			path: "#{__dirname}/test-services/second/ssh/tcp",
			service: '_second._sub._ssh._tcp',
			tags: [ 'second_ssh' ],
			bonjourOpts: { name: 'Second SSH', port: 2345, type: 'ssh', subtypes: [ 'second' ], protocol: 'tcp' }
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

			# Publish a new service that isn't in the registry. We should not
			# expect to see it. In this case, it's an encompassing SSH type.
			bonjourInstance.publish
				name: 'Invalid SSH', port: 5678,
				type: 'ssh', subtypes: [ 'invalid' ], protocol: 'tcp'

		# Stop the dummy services.
		after ->
			bonjourInstance.unpublishAll()
			bonjourInstance.destroy()

		describe 'using invalid parameters', ->
			it '.enumerateServices() should throw an error with an service list', ->
				promise = discoverableServices.findServices('spoon')
				expect(promise).to.eventually.be.rejectedWith(Error, 'services parameter must be an array of service name strings')

			it '.enumerateServices() should throw an error with an invalid timeout', ->
				promise = discoverableServices.findServices([], 'spoon')
				expect(promise).to.eventually.be.rejectedWith(Error, 'timeout parameter must be a number value in milliseconds')

		describe 'using a set of published services', ->
			this.timeout(10000)
			findService = (services, idName) ->
				return _.find services, (service) ->
					return if service.name == idName then true else false

			it 'should return only the gopher and second ssh service using default timeout as a promise', ->
				startTime = _.now()
				discoverableServices.findServices([ '_noweb._sub._gopher._udp', 'second_ssh' ])
				.then (services) ->
					expect(services).to.have.length(2)
					elapsedTime = _.now() - startTime
					expect(elapsedTime).to.be.above(2000)
					expect(elapsedTime).to.be.below(3000)

					gopher = findService(services, 'Gopher')
					expect(gopher.service).to.equal('_noweb._sub._gopher._udp')
					expect(gopher.fqdn).to.equal('Gopher._gopher._udp.local')
					expect(gopher.subtypes).to.deep.equal([ 'noweb' ])
					expect(gopher.port).to.equal(3456)
					expect(gopher.protocol).to.equal('udp')

					privateSsh = findService(services, 'Second SSH')
					expect(privateSsh.service).to.equal('_second._sub._ssh._tcp')
					expect(privateSsh.fqdn).to.equal('Second SSH._ssh._tcp.local')
					expect(privateSsh.subtypes).to.deep.equal([ 'second' ])
					expect(privateSsh.port).to.equal(2345)
					expect(privateSsh.protocol).to.equal('tcp')

			it 'should return both first and second ssh services using default timeout via a callback', (done) ->
				startTime = _.now()
				discoverableServices.findServices [ '_first._sub._ssh._tcp', 'second_ssh' ], 6000, (error, services) ->
					expect(services).to.have.length(2)
					elapsedTime = _.now() - startTime
					expect(elapsedTime).to.be.above(6000)
					expect(elapsedTime).to.be.below(7000)

					mainSsh = findService(services, 'First SSH')
					expect(mainSsh.service).to.equal('_first._sub._ssh._tcp')
					expect(mainSsh.fqdn).to.equal('First SSH._ssh._tcp.local')
					expect(mainSsh.subtypes).to.deep.equal([ 'first' ])
					expect(mainSsh.port).to.equal(1234)
					expect(mainSsh.protocol).to.equal('tcp')

					# We didn't explicitly search for the private SSH services
					# so the subtype is empty and the service is just a vanilla
					# 'ssh' one.
					privateSsh = findService(services, 'Second SSH')
					expect(privateSsh.service).to.equal('_second._sub._ssh._tcp')
					expect(privateSsh.fqdn).to.equal('Second SSH._ssh._tcp.local')
					expect(privateSsh.subtypes).to.deep.equal([ 'second' ])
					expect(privateSsh.port).to.equal(2345)
					expect(privateSsh.protocol).to.equal('tcp')
					done()
				return

	describe '.publishServices()', ->
		this.timeout(10000)

		describe 'using invalid parameters', ->
			it '.publishServices() should throw an error with an service list', ->
				promise = discoverableServices.publishServices('spoon')
				expect(promise).to.eventually.be.rejectedWith(Error, 'services parameter must be an array of service objects')

		describe 'using test services', ->
			findService = (services, idName) ->
				return _.find services, (service) ->
					return if service.name == idName then true else false

			it 'should publish only the gopher service and find only it', ->
				discoverableServices.publishServices([ { name: 'Gopher', identifier: '_noweb._sub._gopher._udp', port: 3456 } ])
				.then ->
					discoverableServices.findServices([ '_noweb._sub._gopher._udp', 'second_ssh' ])
				.then (services) ->
					expect(services).to.have.length(1)
					gopher = findService(services, 'Gopher')
					expect(gopher.service).to.equal('_noweb._sub._gopher._udp')
					expect(gopher.fqdn).to.equal('Gopher._gopher._udp.local')
					expect(gopher.subtypes).to.deep.equal([ 'noweb' ])
					expect(gopher.port).to.equal(3456)
					expect(gopher.protocol).to.equal('udp')
				.finally ->
					discoverableServices.unpublishServices()

			it 'should publish only the gopher service and find only it', ->
				discoverableServices.publishServices([ { name: 'Gopher', identifier: '_noweb._sub._gopher._udp', host: 'gopher.local', port: 3456 } ])
				.then ->
					discoverableServices.findServices([ '_noweb._sub._gopher._udp', 'second_ssh' ])
				.then (services) ->
					expect(services).to.have.length(1)
					gopher = findService(services, 'Gopher')
					expect(gopher.service).to.equal('_noweb._sub._gopher._udp')
					expect(gopher.fqdn).to.equal('Gopher._gopher._udp.local')
					expect(gopher.subtypes).to.deep.equal([ 'noweb' ])
					expect(gopher.port).to.equal(3456)
					expect(gopher.host).to.equal('gopher.local')
					expect(gopher.protocol).to.equal('udp')

					discoverableServices.unpublishServices()

			it 'should publish all services and find them', ->
				discoverableServices.publishServices [
					{ identifier: '_first._sub._ssh._tcp', name: 'First SSH' , port: 1234 }
					{ identifier: 'second_ssh', name: 'Second SSH' , port: 2345 }
					{ identifier: '_noweb._sub._gopher._udp', name: 'Gopher', port: 3456 }

				]
				.then ->
					discoverableServices.findServices([ '_first._sub._ssh._tcp', '_noweb._sub._gopher._udp', 'second_ssh' ])
				.then (services) ->
					expect(services).to.have.length(3)

					gopher = findService(services, 'Gopher')
					expect(gopher.service).to.equal('_noweb._sub._gopher._udp')
					expect(gopher.fqdn).to.equal('Gopher._gopher._udp.local')
					expect(gopher.subtypes).to.deep.equal([ 'noweb' ])
					expect(gopher.port).to.equal(3456)
					expect(gopher.protocol).to.equal('udp')

					mainSsh = findService(services, 'First SSH')
					expect(mainSsh.service).to.equal('_first._sub._ssh._tcp')
					expect(mainSsh.fqdn).to.equal('First SSH._ssh._tcp.local')
					expect(mainSsh.subtypes).to.deep.equal([ 'first' ])
					expect(mainSsh.port).to.equal(1234)
					expect(mainSsh.protocol).to.equal('tcp')

					privateSsh = findService(services, 'Second SSH')
					expect(privateSsh.service).to.equal('_second._sub._ssh._tcp')
					expect(privateSsh.fqdn).to.equal('Second SSH._ssh._tcp.local')
					expect(privateSsh.subtypes).to.deep.equal([ 'second' ])
					expect(privateSsh.port).to.equal(2345)
					expect(privateSsh.protocol).to.equal('tcp')
				.finally ->
					discoverableServices.unpublishServices()

			it 'should publish single service only to local IPv4 loopback interface', ->
				# This is a rough check, as by default every Darwin based platform
				# runs MDNS by default. It is assumed that every other platform (such as
				# Linux/FreeBSD/Windows) is *not* running a Bonjour based protocol.
				# If it is, this test will fail as it will not be able to bind to port 5354.
				if process.platform isnt 'darwin'
					discoverableServices.publishServices [
						{ identifier: '_first._sub._ssh._tcp', name: 'First SSH', port: 1234 }
					], { mdnsInterface: '127.0.0.1' }
					.then ->
						discoverableServices.findServices([ '_first._sub._ssh._tcp' ])
					.then (services) ->
						mainSsh = findService(services, 'First SSH')
						expect(mainSsh.service).to.equal('_first._sub._ssh._tcp')
						expect(mainSsh.fqdn).to.equal('First SSH._ssh._tcp.local')
						expect(mainSsh.subtypes).to.deep.equal([ 'first' ])
						expect(mainSsh.port).to.equal(1234)
						expect(mainSsh.protocol).to.equal('tcp')
						expect(mainSsh.referer.address).to.equal('127.0.0.1')
					.finally ->
						discoverableServices.unpublishServices()
