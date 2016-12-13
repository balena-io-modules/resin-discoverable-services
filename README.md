resin-discoverable-services
===========================

> Discover all resin registered services from the local network.

[![npm version](https://badge.fury.io/js/resin-discoverable-services.svg)](http://badge.fury.io/js/resin-discoverable-services)
[![dependencies](https://david-dm.org/resin-io-modules/resin-discoverable-services.svg)
[![Build Status](https://travis-ci.org/resin-io-modules/resin-discoverable-services.svg?branch=master)](https://travis-ci.org/resin-io-modules/resin-discoverable-services)
[![Gitter](https://badges.gitter.im/Join Chat.svg)](https://gitter.im/resin-io-modules/chat)

Role
----

The intention of this module is to provide a way to discover zeroconf services advertised by Resin.io components and devices on a local network.

Installation
------------

Install `resin-discoverable-services` by running:

```sh
$ npm install --save resin-discoverable-services
```

API
-------------

This module exports three methods:

#### setRegistryPath(path)

This informs the module where to search for valid services to register with itself. By default this is the `services` directory within it.
Service defintions are defined as a set of nested directories, and take the form:

    `[<subtype>/]<type>/<protocol>`

A `tags.json` file may exist in the lowest level directory in a service definition and consists of an array of strings, each of which is a 'shortened name' for the service defined, eg.:

    `[ 'serviceShortName', 'reallyShort' ]`

#### enumerateServices([callback(error, services)])

Returns the list of currently registered service definitions. Service definitions are returned in the standard service form:

    `{ service: `[_<subtype>._sub]._<type>._protocol`, tags: [ [tagNames] ] }`

**Notice** Should a callback not be provided, then the method will return a resolvable Promise.

Only registered services returned by the `enumerateServices()` method may be used to find services on the local network.

Should a callback not be provided, then the method will return a resolvable Promise.

#### findServices(services, [[timeout], [callback(error, services)])

Searches for any occurrences of the specified services on the local network. Services are passed in the standard service form, or as a tag associated with that service.

**Notice** Should a callback not be provided, then the method will return a resolvable Promise.

The timeout value is the length of time in milliseconds that the module will search for before returning any results. If no value is passed, it defaults to 2000ms.

The method returns an array of services that conform to those registered. Each service information object consists of:

* `String service`: The service name as passed, or to which a passed tag references, to `findServices()`.
* `Array[String] addresses`: An array denoting either an IPv4 or IPv6 addresses where the service is located.
* `String name`: The name of the service, eg. `My Service`.
* `String fqdn`: The fully qualified domain name of the service, eg. `My Service._ssh._tcp.local`.
* `String host`: The machine node name where the service is located, eg. `myMachine.local`.
* `Number port`: 222,
* `String type`: The type of the service, eg. `ssh`.
* `String protocol`: The protocol the service uses, eg. `tcp`.
* `Array[String] subtypes`: An array of subtypes pertaining to this service, these will only be filled in should the specific subtype have been used in the method call.
* `Object txt`: Any text records that go along with the service, eg. 'username'.
* `Object referer`: An object containing:
    - `String address`: Address of the referer.
    - `String family`: IP family that the referer used (IPv4 or IPv6).
    - `Number port`: The port on which the referer runs.

#### publishServices(services, [options, [callback(error, services)]])

Publishes any valid service to the network. If a call to this method is made then a corresponding call to `unpublishServices()` **must** be made before process exit to ensure any existing network sockets are finalised.

**Notice** Should a callback not be provided, then the method will return a resolvable Promise.

`services` is an array of objects, each of which contains:

* `String identifier`: The standard service form of the service to publish, or a tag associated with that service.
* `String name`: The name under which to publish the service, (eg. `Resin SSH`).
* `Number port`: The port number to advertise the service as running on.
* `String host`: An optional host name to publish the service as running on. This is useful for proxying.

`options` is an object allowing publishing options to be passed:

* `String mdnsInterface`: An IPv4 or IPv6 address of a current valid interface with which to bind the MDNS service to (if unset, first available interface).


#### unpublishServices([callback])

Unpublishes all services currently published to the network. This method **must** be called prior to process exit should any calls to `publishServices()` have been made.

**Notice** Should a callback not be provided, then the method will return a resolvable Promise.

Support
-------

If you're having any problem, please [raise an issue](https://github.com/resin-io-modules/resin-discoverable-services/issues/new) on GitHub and the Resin.io team will be happy to help.

Tests
-----

Run the test suite by doing:

```sh
$ gulp test
```

Contribute
----------

- Issue Tracker: [github.com/resin-io-modules/resin-discoverable-services/issues](https://github.com/resin-io-modules/resin-discoverable-services/issues)
- Source Code: [github.com/resin-io-modules/resin-discoverable-services](https://github.com/resin-io-modules/resin-discoverable-services)

Before submitting a PR, please make sure that you include tests, and that [coffeelint](http://www.coffeelint.org/) runs without any warning:

```sh
$ gulp lint
```

License
-------

The project is licensed under the Apache 2.0 license.
