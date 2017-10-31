
path = require 'path'
pad = require 'pad' 

types = ['string', 'boolean', 'integer', 'array']

###
# parameters(config)

## About options

Options are defined at the "config" level or for each command.

## About main

Main is what's left after the options. Like options, "main" is 
defined at the "config" level or for each command.

Parameters are defined with the following properties
*   name:     name of the two dash parameter in the command (eg "--my_name") and in the returned parse object unless label is defined.
*   label:    not yet implemented, see name
*   shortcut: name of the one dash parameter in the command (eg "-n"), must be one charactere
*   required: boolean, throw an exception when true and the parameter is not defined
*   type:     one of 'string', 'boolean', 'integer' or 'array'

###
Parameters = (config = {}) ->
  @config = config
  # Sanitize options
  options = (command) ->
    for option in command.options
      # Access option by key
      do (option) ->
        command.options.__defineGetter__ option.name, -> option
      option.type ?= 'string'
      throw Error "Invalid option type #{JSON.stringify option.type}" if types.indexOf(option.type) is -1
      command.shortcuts[option.shortcut] = option.name
      options.one_of = [options.one_of] if typeof options.one_of is 'string'
      throw Error "Invalid option one_of \"#{JSON.stringify option.one_of}\"" if options.one_of and not Array.isArray options.one_of
  # An object where key are command and values are object map between shortcuts and names
  config.shortcuts = {}
  config.options ?= []
  options config
  config.command ?= 'command'
  config.commands ?= []
  config.commands = [config.commands] unless Array.isArray config.commands
  makeCommand = (command) ->
    config.commands.__defineGetter__ command.name, -> command
    command.strict ?= config.strict
    command.shortcuts = {}
    command.options ?= []
    command.options = [command.options] unless Array.isArray command.options
    options command
  for command in config.commands
    makeCommand command
  unless config.commands.help
    if config.commands.length
      commands = 
        name: 'help'
        description: "Display help information about #{config.name}"
        main:
          name: 'name'
          description: 'Help about a specific command'
      config.commands.push commands
      makeCommand commands
    else 
      config.options.push 
        name: 'help'
        shortcut: 'h'
        description: "Display help information"
  @

###

## `run([argv])`

Parse the arguments and execute the module defined by the "module" option.

You should only pass the parameters and the not the script name.

Example

  result = parameters(
    commands: [
      name: 'start'
      run: function(){ return 'something'; }
      options: [
        name: 'debug'
      ]
    ]
  ).run ['start', '-d', 'Hello']

###
Parameters.prototype.run = (argv = process, args...) ->
  params = @parse argv
  if params[@config.command]
    run = @config.commands[params[@config.command]].run
  else
    run = @config.run
  # Load the module
  run = load run if typeof run is 'string'
  run.call @, args..., params, argv, @config
  

###

## `parse([argv])`

Convert process arguments into a usable object. Argument may
be in the form of a string or an array. If not provided, it 
parse the arguments present in  `process.argv`.

You should only pass the parameters and the not the script name.

Example

  params = argv.parse ['start', '--watch', __dirname, '-s', 'my', '--command']
  params.should.eql
    action: 'start'
    watch: __dirname
    strict: true
    command: 'my --command'

###
Parameters.prototype.parse = (argv = process) ->
  argv = argv.split ' ' if typeof argv is 'string'
  index = 0
  # Remove node and script argv elements
  if argv is process
    index = 2
    argv = argv.argv
  # Extracted parameters
  params = {}
  parse = (config) =>
    # Read options
    while true
      break if argv.length is index or argv[index][0] isnt '-'
      key = argv[index++]
      shortcut = key[1] isnt '-'
      key = key.substring (if shortcut then 1 else 2), key.length
      shortcut = key if shortcut
      key = config.shortcuts[shortcut] if shortcut
      option = config.options?[key]
      throw Error "Invalid option #{JSON.stringify key}" if not shortcut and config.strict and not option
      throw Error "Invalid shortcut '#{shortcut}'" if shortcut and not option
      # Auto discovery
      unless option
        type = if argv[index] and argv[index][0] isnt '-' then 'string' else 'boolean'
        option = name: key, type: type
      switch option.type
        when 'boolean'
          params[key] = true
        when 'string'
          value = argv[index++]
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" unless value?
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" if value[0] is '-'
          params[key] = value
        when 'integer'
          value = argv[index++]
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" unless value?
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" if value[0] is '-'
          params[key] = parseInt value, 10
        when 'array'
          value = argv[index++]
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" unless value?
          throw Error "Invalid Option: no value found for option #{JSON.stringify key}" if value[0] is '-'
          params[key] ?= []
          params[key].push value.split(',')...
    # Check against required options
    options = config.options
    if options then for option in options
      if option.required
        throw Error "Required option argument \"#{option.name}\"" unless params.help or params[option.name]?
      if option.one_of
        values = params[option.name]
        values = [values] unless Array.isArray values
        for value in values
          throw Error "Invalid value \"#{value}\" for option \"#{option.name}\"" unless value in option.one_of
    # We still have some argument to parse
    if argv.length isnt index
      # Store the full command in the return object
      main = argv.slice(index).join(' ')
      if config.main
        params[config.main.name] = main
      else
        if config.commands?[argv[index]]
          config = @config.commands[argv[index]]
          params[@config.command] = argv[index++]
          parse config, argv
        else
          throw Error "Fail to parse end of command \"#{main}\""
    # Check against required main
    main = config.main
    if main
      if main.required
        throw Error "Required main argument \"#{main.name}\"" unless params[main.name]?
      # params[main.name] ?= null
    params
  # If they are commands (other than help) and no arguments are provided,
  # we default to the help action
  if @config.commands.length and argv.length is index
    argv.push 'help'
  if @config.commands.length and argv[index].substr(0,1) isnt '-'
    config = @config.commands[argv[index]]
    throw Error "Invalid command '#{argv[index]}'" unless config
    params[@config.command] = argv[index++]
  else
    config = @config
  params = parse config, argv
  # Enrich params with default values
  if params[@config.command]
    for option in @config.commands[params[@config.command]].options
      params[option.name] ?= option.default if option.default?
  for option in @config.options
    params[option.name] ?= option.default if option.default?
  params

###

## `stringify([script], params)`

Convert an object into process arguments.

###
Parameters.prototype.stringify = (params, options={}) ->
  argv = if options.script then [process.execPath, options.script] else []
  keys = {}
  # Validate command
  if params[@config.command]
    throw Error "Invalid command '#{params[@config.command]}'" unless @config.commands[params[@config.command]]
  # Enrich params with default values
  if params[@config.command]
    for option in @config.commands[params[@config.command]].options
      params[option.name] ?= option.default if option.default?
  for option in @config.options
    params[option.name] ?= option.default if option.default?
  # Stringify
  stringify = (config) =>
    for option in config.options
      key = option.name
      keys[key] = true
      value = params[key]
      # Validate required value
      throw Error "Required option argument \"#{key}\"" if option.required and not value?
      # Validate value against option "one_of"
      if value? and option.one_of
        value = [value] unless Array.isArray value
        for val in value
          throw Error "Invalid value \"#{val}\" for option \"#{option.name}\"" unless val in option.one_of
      # Serialize
      if value then switch option.type
        when 'boolean'
          argv.push "--#{key}"
        when 'string', 'integer'
          argv.push "--#{key}"
          argv.push "#{value}"
        when 'array'
          argv.push "--#{key}"
          argv.push "#{value.join ','}"
    if config.main
      value = params[config.main.name]
      throw Error "Required main argument \"#{config.main.name}\"" if config.main.required and not value?
      keys[config.main.name] = value
      argv.push value if value?
  stringify @config
  if params[@config.command]
    config = @config.commands[params[@config.command]]
    argv.push params[@config.command]
    keys[@config.command] = params[@config.command]
    stringify config
  # Check keys
  for key, value of params
    continue if keys[key]
    throw Error "Invalid option #{JSON.stringify key}" if @config.strict
    if typeof value is 'boolean'
      argv.push "--#{key}" if value
    else if typeof value is 'undefined' or value is null
      # nothing
    else
      argv.push "--#{key}"
      argv.push "#{value}"
  argv

###

## `help([command])`

Return a string describing the usage of the overall command or one of its
command.

###
Parameters.prototype.help = (command) ->
    config = @config.commands[command]
    throw Error "Invalid command \"#{command}\"" if command? and not config
    describeOption = (option, pad_option, pad_description) ->
      shortcut = if option.shortcut then "-#{option.shortcut} " else ''
      content = ' '.repeat pad_option
      content += pad "#{shortcut}--#{option.name}", pad_description - pad_option
      content += option.description
      content += '\n'
    describeCommand = (config) ->
      content = pad "    #{config.name}", 24
      content += config.description
      content += '\n'
      if config.options then for option in config.options
        content += describeOption option, 6, 26
      if config.main
        content += pad "      #{config.main.name}", 26
        content += config.main.description
        content += '\n'
      content
    if command and command isnt 'help'
      # Command help
      config = @config.commands[command]
      synopsis = @config.name + ' ' + command
      if config.options.length
        options = 'options...'
        options = "[#{options}]" unless (config.options.filter (o) -> o.required).length
        synopsis += " #{options}"
      if config.main
        main = "#{config.main.name}"
        main = "[#{main}]" unless config.main.required
        synopsis += " #{main}"
      content = """
      NAME
          #{@config.name} #{command} - #{config.description}
      SYNOPSIS
          #{synopsis}
      DESCRIPTION

      """
      content += describeCommand config
    else
      # Full help
      content = """
      NAME
          #{@config.name} - #{@config.description}

      """
      content += 'SYNOPSIS\n'
      content += "    #{@config.name}"
      content += ' command' if @config.commands.length
      content += ' [options...]'
      content += '\n'
      if @config.commands.length
        content += '    where command is one of'
        content += '\n'
      for command in @config.commands
        content += pad "      #{command.name}", 24
        content += command.description
        content += '\n'
      content += 'DESCRIPTION\n'
      # Describe each option
      for option in @config.options
        content += describeOption option, 4, 24
        # shortcut = if option.shortcut then "-#{option.shortcut} " else ''
        # content += pad "    #{shortcut}--#{option.name}", 24
        # content += option.description
        # content += '\n'
      if @config.main
        content += pad "    #{@config.main.name}", 24
        content += @config.main.description
        content += '\n'
      # Describe each command
      for command in @config.commands
        content += describeCommand command
      # Add examples
      content += 'EXAMPLES\n'
      if @config.commands.length
        content += "    #{@config.name} help       Show this message"
      else
        content += "    #{@config.name} --help     Show this message"
      content += '\n'
      content

module.exports = (config) ->
  new Parameters config
module.exports.Parameters = Parameters

load = (module) ->
  module = if module.substr(0, 1) is '.'
  then path.resolve process.cwd(), module
  else module
  require.main.require module
