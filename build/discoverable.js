
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
var Promise, _, bonjour, fs, registryPath, retrieveServices, services;

Promise = require('bluebird');

fs = Promise.promisifyAll(require('fs'));

bonjour = require('bonjour');

_ = require('lodash');

_.memoize.Cache = Map;

registryPath = __dirname + "/../services";


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

services = _.memoize(retrieveServices);


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
  return services.cache.clear();
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
  return services().asCallback(callback);
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
 * @param {Array} services - A string array of service names or tags
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
  var bonjourInstance, createBrowser, findValidService;
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
  bonjourInstance = bonjour();
  createBrowser = function(serviceName, subtypes, type, protocol) {
    return new Promise(function(resolve) {
      var browser, foundServices;
      foundServices = [];
      browser = bonjourInstance.find({
        type: type,
        subtypes: subtypes,
        protocol: protocol
      }, function(service) {
        service.service = serviceName;
        return foundServices.push(service);
      });
      return setTimeout(function() {
        browser.stop();
        return resolve(foundServices);
      }, timeout);
    });
  };
  findValidService = function(serviceName, knownServices) {
    return _.find(knownServices, function(service) {
      if (service.service === serviceName) {
        return true;
      } else {
        return _.indexOf(service.tags, serviceName) !== -1;
      }
    });
  };
  return retrieveServices().then(function(validServices) {
    var serviceBrowsers;
    serviceBrowsers = [];
    services.forEach(function(service) {
      var protocol, registeredService, subtypes, type, types;
      if ((registeredService = findValidService(service, validServices)) != null) {
        types = registeredService.service.match(/^(_(.*)\._sub\.)?_(.*)\._(.*)$/);
        if (types[1] === void 0 && types[2] === void 0) {
          subtypes = [];
        } else {
          subtypes = [types[2]];
        }
        if ((types[3] != null) && (types[4] != null)) {
          type = types[3];
          protocol = types[4];
          return serviceBrowsers.push(createBrowser(registeredService.service, subtypes, type, protocol));
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
    return bonjourInstance.destroy();
  }).asCallback(callback);
});
