gulp        = require 'gulp'
less        = require 'gulp-less'
concat      = require 'gulp-concat'
browserify  = require 'gulp-browserify'
zip         = require 'gulp-zip'
jeditor     = require 'gulp-json-editor'

Package     = require './package.json'

project =
  dist:     './dist'
  build:    './build'
  src:      './app/**/*.coffee'
  static:   './static/**'
  font:     './style/font/**'
  style:    './style/index.less'
  manifest: './manifest.json'

gulp.task 'default', ['pack']
gulp.task 'build', ['src', 'static', 'style', 'manifest']

gulp.task 'src', ->
  gulp.src('./app/index.coffee',  read: false)
    .pipe(browserify({
      transform:  ['coffeeify']
      extensions: ['.coffee']
    }))
    .pipe(concat('app.js'))
    .pipe(gulp.dest(project.build))

gulp.task 'static', ->
  gulp.src(project.static)
    .pipe(gulp.dest(project.build))

gulp.task 'font', ->
  gulp.src(project.font)
    .pipe(gulp.dest("#{project.build}/font"))

gulp.task 'style', ['font'], ->
  gulp.src(project.style)
    .pipe(less())
    .pipe(concat('app.css'))
    .pipe(gulp.dest(project.build))

gulp.task 'manifest', ->
  gulp.src(project.manifest)
    .pipe(jeditor((json) ->
      json.version = Package.version
      json
    )).pipe(gulp.dest(project.build))

gulp.task 'pack', ['build'], ->
  gulp.src("#{project.build}/**")
    .pipe(zip("#{Package.name}-#{Package.version}.zip"))
    .pipe(gulp.dest(project.dist))
