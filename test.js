var Bonjour = require('bonjour');

var MdnsServer = require('bonjour/lib/mdns-server')
var originalRespone = MdnsServer.prototype._respondToQuery
MdnsServer.prototype._respondToQuery = function (query) {
	if (!this.mdns.respondOverridden) {
		var originalRespond = this.mdns.respond;
		this.mdns.respond = function (response) {
			console.log('responding', response);
			originalRespond.apply(this, arguments);
		}
		this.mdns.respondOverridden = true;
	}

	console.log('got query', query);
	return originalRespone.apply(this, arguments)
}

var instance = new Bonjour();
instance.publish({ name: 'quickTest', type: 'http', port: 3000 });

setTimeout(() => {
	var childProcess = require('child_process')
	avahiBrowse = childProcess.spawn('avahi-browse', ['_http._tcp', '--resolve', '--terminate'])
	avahiBrowse.stdout.pipe(process.stdout)
	avahiBrowse.stderr.pipe(process.stderr)
}, 1000);

setTimeout(() => {
	instance.unpublishAll()
	instance.destroy()
}, 5000);
