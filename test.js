var Bonjour = require('bonjour');
var instance = new Bonjour();
instance.publish({ name: 'quickTest', type: 'http', port: 3000 });

setTimeout(() => {
	var childProcess = require('child_process')
	avahiBrowse = childProcess.spawn('avahi-browse', ['--all', '--resolve', '--terminate'])
	avahiBrowse.stdout.pipe(process.stdout)
	avahiBrowse.stderr.pipe(process.stderr)
}, 1000);

setTimeout(() => {
	instance.unpublishAll()
	instance.destroy()
}, 5000);
