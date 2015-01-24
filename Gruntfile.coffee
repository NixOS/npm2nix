module.exports = (grunt) ->

  # Project configuration.
  grunt.initConfig
    coffee:
      app:
        expand: true
        cwd: 'src'
        src: ['**/*.coffee']
        dest: 'lib'
        ext: '.js'
    watch:
      app:
        files: '**/*.coffee'
        tasks: ['coffee']
    bump:
      options:
        npm: false

  # These plugins provide necessary tasks.
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-release'

  # Default task.
  grunt.registerTask 'default', ['coffee']
