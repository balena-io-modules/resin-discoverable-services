gulp = require('gulp')
mocha = require('gulp-mocha')
gutil = require('gulp-util')
coffee = require('gulp-coffee')

OPTIONS =
	files:
		coffee: [ 'lib/**/*.coffee', 'tests/**/*.spec.coffee', 'gulpfile.coffee' ]
		app: 'lib/**/*.coffee'
		tests: 'tests/**/*.spec.coffee'

gulp.task 'build', ->
	gulp.src(OPTIONS.files.app)
		.pipe(coffee(header: true)).on('error', gutil.log)
		.pipe(gulp.dest('build/'))

gulp.task 'test', ['build'], ->
	gulp.src(OPTIONS.files.tests, read: false)
		.pipe(mocha({}))

gulp.task 'watch', ['test'], ->
	gulp.watch(OPTIONS.files.coffee, ['test'])
