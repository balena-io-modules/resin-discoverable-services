
/*
Copyright 2016 Resin.io

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */
var Promise, _, bonjour, determineServiceInfo, findValidService, fs, hasValidInterfaces, os, publishInstance, registryPath, registryServices, retrieveServices,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; },
  slice = [].slice;

Promise = require('bluebird');

fs = Promise.promisifyAll(require('fs'));

os = require('os');

bonjour = require('bonjour');

_ = require('lodash');

_.memoize.Cache = Map;

registryPath = __dirname + "/../services";

publishInstance = null;


/*
 * @summary Scans the registry path hierarchy to determine service types.
 * @function
 * @private
 */

retrieveServices = function() {
  var foundPaths, scanDirectory;
  foundPaths = [];
  scanDirectory = function(parentPath, localPath) {
    var foundDirectories;
    foundDirectories = [];
    return fs.readdirAsync(parentPath).then(function(paths) {
      return Promise.map(paths, function(path) {
        return fs.statAsync(parentPath + "/" + path).then(function(stat) {
          if (stat.isDirectory()) {
            return foundDirectories.push(path);
          }
        });
      });
    }).then(function() {
      if (foundDirectories.length === 0) {
        return foundPaths.push(localPath);
      } else {
        return Promise.map(foundDirectories, function(path) {
          return scanDirectory(parentPath + "/" + path, localPath + "/" + path);
        });
      }
    });
  };
  return scanDirectory(registryPath, '').then(function() {
    var services;
    services = [];
    return Promise.map(foundPaths, function(path) {
      var components, service, tags;
      components = _.split(path, '/');
      components.shift();
      if (components.length >= 2 || components.length <= 3) {
        service = '';
        tags = [];
        if (components.length === 3) {
          service = "_" + components[0] + "._sub.";
          components.shift();
        }
        service += "_" + components[0] + "._" + components[1];
        return fs.readFileAsync("" + registryPath + path + "/tags.json", {
          encoding: 'utf8'
        }).then(function(data) {
          var json;
          json = JSON.parse(data);
          if (!_.isArray(json)) {
            throw new Error();
          }
          return tags = json;
        })["catch"](function(err) {
          if (err.code !== 'ENOENT') {
            throw new Error("tags.json for " + service + " service defintion is incorrect");
          }
        }).then(function() {
          return services.push({
            service: service,
            tags: tags
          });
        });
      }
    })["return"](services);
  });
};

registryServices = _.memoize(retrieveServices);


/*
 * @summary Determines if a service is valid.
 * @function
 * @private
 */

findValidService = function(serviceIdentifier, knownServices) {
  return _.find(knownServices, function(arg) {
    var service, tags;
    service = arg.service, tags = arg.tags;
    return indexOf.call([service].concat(slice.call(tags)), serviceIdentifier) >= 0;
  });
};


/*
 * @summary Retrieves information for a given services string.
 * @function
 * @private
 */

determineServiceInfo = function(service) {
  var info, types;
  info = {};
  types = service.service.match(/^(_(.*)\._sub\.)?_(.*)\._(.*)$/);
  if ((types[1] == null) && (types[2] == null)) {
    info.subtypes = [];
  } else {
    info.subtypes = [types[2]];
  }
  if ((types[3] != null) && (types[4] != null)) {
    info.type = types[3];
    info.protocol = types[4];
  }
  return info;
};


/*
 * @summary Ensures valid network interfaces exist
 * @function
 * @private
 */

hasValidInterfaces = function() {
  return _.some(os.networkInterfaces(), function(value) {
    return _.some(value, {
      internal: false
    });
  });
};


/*
 * @summary Sets the path which will be examined for service definitions.
 * @function
 * @public
 *
 * @description
 * Should no parameter be passed, or this method not called, then the default
 * path is the 'services' directory that exists within the module's directory
 * hierarchy.
 *
 * @param {String} path - New path to use as the service registry.
 *
 * @example
 * discoverableServices.setRegistryPath("/home/heds/discoverable_services")
 */

exports.setRegistryPath = function(path) {
  if (path == null) {
    path = __dirname + "/../services";
  }
  if (!_.isString(path)) {
    throw new Error('path parameter must be a path string');
  }
  registryPath = path;
  return registryServices.cache.clear();
};


/*
 * @summary Enumerates all currently registered services available for discovery.
 * @function
 * @public
 *
 * @description
 * This function allows promise style if the callback is omitted.
 *
 * @param {Function} callback - callback (error, services)
 *
 * @example
 * discoverableServices.enumerateServices (error, services) ->
 *   throw error if error?
 *   # services is an array of service objects holding type/subtype and any tagnames associated with them
 *   console.log(services)
 */

exports.enumerateServices = function(callback) {
  return registryServices().asCallback(callback);
};


/*
 * @summary Listens for all locally published services, returning information on them after a period of time.
 * @function
 * @public
 *
 * @description
 * This function allows promise style if the callback is omitted. Should the timeout value be missing
 * then a default timeout of 2000ms is used.
 *
 * @param {Array} services - A string array of service identifiers or tags
 * @param {Number} timeout - A timeout in milliseconds before results are returned. Defaults to 2000ms
 * @param {Function} callback - callback (error, services)
 *
 * @example
 * discoverableServices.findServices([ '_resin-device._sub._ssh._tcp' ], 5000, (error, services) ->
 *	throw error if error?
 *   # services is an array of every service that conformed to the specified search parameters
 *   console.log(services)
 */

exports.findServices = Promise.method(function(services, timeout, callback) {
  var createBrowser, findInstance;
  if (timeout == null) {
    timeout = 2000;
  } else {
    if (!_.isNumber(timeout)) {
      throw new Error('timeout parameter must be a number value in milliseconds');
    }
  }
  if (!_.isArray(services)) {
    throw new Error('services parameter must be an array of service name strings');
  }
  if (!hasValidInterfaces()) {
    throw new Error('At least one non-loopback interface must be present to bind to');
  }
  findInstance = bonjour();
  createBrowser = function(serviceIdentifier, subtypes, type, protocol) {
    return new Promise(function(resolve) {
      var browser, foundServices;
      foundServices = [];
      browser = findInstance.find({
        type: type,
        subtypes: subtypes,
        protocol: protocol
      }, function(service) {
        service.service = serviceIdentifier;
        return foundServices.push(service);
      });
      return setTimeout(function() {
        browser.stop();
        return resolve(foundServices);
      }, timeout);
    });
  };
  return registryServices().then(function(validServices) {
    var serviceBrowsers;
    serviceBrowsers = [];
    services.forEach(function(service) {
      var registeredService, serviceDetails;
      if ((registeredService = findValidService(service, validServices)) != null) {
        serviceDetails = determineServiceInfo(registeredService);
        if ((serviceDetails.type != null) && (serviceDetails.protocol != null)) {
          return serviceBrowsers.push(createBrowser(registeredService.service, serviceDetails.subtypes, serviceDetails.type, serviceDetails.protocol));
        }
      }
    });
    return Promise.all(serviceBrowsers).then(function(services) {
      services = _.flatten(services);
      _.remove(services, function(entry) {
        return entry === null;
      });
      return services;
    });
  })["finally"](function() {
    return findInstance.destroy();
  }).asCallback(callback);
});


/*
 * @summary Publishes all available services
 * @function
 * @public
 *
 * @description
 * This function allows promise style if the callback is omitted.
 * Note that it is vital that any published services are unpublished during exit of the process using `unpublishServices()`.
 *
 * @param {Array} services - An object array of service details. Each service object is comprised of:
 * @param {String} services.identifier - A string of the service identifier or an associated tag
 * @param {String} services.name - A string of the service name to advertise as
 * @param {String} services.host - A specific hostname that will be used as the host (useful for proxying or psuedo-hosting). Defaults to current host name should none be given
 * @param {Number} services.port - The port on which the service will be advertised
 *
 * @example
 * discoverableServices.publishServices([ { service: '_resin-device._sub._ssh._tcp', host: 'server1.local', port: 9999 } ])
 */

exports.publishServices = Promise.method(function(services, callback) {
  if (!_.isArray(services)) {
    throw new Error('services parameter must be an array of service objects');
  }
  if (!hasValidInterfaces()) {
    throw new Error('At least one non-loopback interface must be present to bind to');
  }
  return registryServices().then(function(validServices) {
    return services.forEach(function(service) {
      var publishDetails, publishedServices, registeredService, serviceDetails;
      if ((service.identifier != null) && (service.name != null) && ((registeredService = findValidService(service.identifier, validServices)) != null)) {
        serviceDetails = determineServiceInfo(registeredService);
        if ((serviceDetails.type != null) && (serviceDetails.protocol != null) && (service.port != null)) {
          if (publishInstance == null) {
            publishInstance = bonjour();
          }
          publishDetails = {
            name: service.name,
            port: service.port,
            type: serviceDetails.type,
            subtypes: serviceDetails.subtypes,
            protocol: serviceDetails.protocol
          };
          if (service.host != null) {
            publishDetails.host = service.host;
          }
          publishInstance.publish(publishDetails);
          return publishedServices = true;
        }
      }
    });
  }).asCallback(callback);
});


/*
 * @summary Unpublishes all available services
 * @function
 * @public
 *
 * @description
 * This function allows promise style if the callback is omitted.
 * This function must be called before process exit to ensure used sockets are destroyed.
 *
 * @example
 * discoverableServices.unpublishServices()
 */

exports.unpublishServices = function(callback) {
  if (publishInstance == null) {
    return Promise.resolve().asCallback(callback);
  }
  return publishInstance.unpublishAll(function() {
    publishInstance.destroy();
    publishInstance = null;
    return Promise.resolve().asCallback(callback);
  });
};
