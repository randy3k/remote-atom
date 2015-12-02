{CompositeDisposable}  = require 'atom'
net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
status-message = require './status-message'

class FileHandler
    settings: {}

    constructor: (session) ->
        @session = session

    create: ->
        @tempfile = path.join(os.tmpdir(), randomstring(10), @basename)
        console.log "[ratom] create #{@tempfile}"
        dirname = path.dirname(@tempfile)
        mkdirp.sync(dirname)
        @fd = fs.openSync(@tempfile, 'w')

    write: (str) ->
        fs.writeSync(@fd, str)

    open: ->
        fs.closeSync @fd
        console.log "[ratom] opening #{@tempfile}"
        # register events
        atom.workspace.open(@tempfile, activatePane:true).then (editor) =>
            @handle_connection(editor)

    handle_connection: (editor) ->
        atom.focus()
        buffer = editor.getBuffer()
        @subscriptions = new CompositeDisposable
        @subscriptions.add buffer.onDidSave =>
            @save()
        @subscriptions.add buffer.onDidDestroy =>
            @close()

    save: ->
        if not @session.alive
            console.log "[ratom] Error saving #{path.basename @tempfile} to #{@remoteAddress}"
            status-message.display "Error saving #{path.basename @tempfile} to #{@remoteAddress}", 2000
            return
        console.log "[ratom] saving #{path.basename @tempfile} to #{@remoteAddress}"
        status-message.display "Saving #{path.basename @tempfile} to #{@remoteAddress}", 2000
        @session.send "save"
        @session.send "token: #{@token}"
        data = fs.readFileSync(@tempfile)
        @session.send "data: " + Buffer.byteLength(data)
        @session.send data

    close: ->
        console.log "[ratom] closing #{path.basename @tempfile}"
        # try to close session
        @session.close()
        @subscriptions.dispose()

class Session
    should_parse_data: false
    readbytes: 0
    nconn: 0

    constructor: (socket) ->
        @socket = socket
        @send "Atom "+ atom.getVersion()
        @alive = true
        socket.on "data", (chunk) =>
            @parse_chunk(chunk)
        socket.on "close", =>
            if @alive
                @alive = false
                console.log "[ratom] connection lost!"
                status-message.display "Connection lost!", 5000

    parse_chunk: (chunk) ->
        if chunk
            chunk = chunk.toString("utf8")
            match = /\n$/.test chunk
            chunk = chunk.replace /\n$/, ""
            lines = chunk.split "\n"
            for line,i in lines
                if i < lines.length-1 or match
                    line = line + "\n"
                @parse_line(line)

    parse_line: (line) ->
        if @should_parse_data
            @parse_data(line)
        else if line.match /open\n/
            @file = new FileHandler(@)
            @readbytes = 0
            @nconn += 1
        else
            @parse_setting(line)

    parse_data: (line) ->
        if @readbytes < @file.datasize
            @readbytes += Buffer.byteLength(line)
            # remove trailing newline if necessary
            if @readbytes == @file.datasize + 1 and line.slice(-1) is "\n"
                line = line.slice(0, -1)
            @file.write(line)
        if @readbytes >= @file.datasize
            @should_parse_data = false
            @file.open()

    parse_setting: (line) ->
        m = line.match /([a-z\-]+?)\s*:\s*(.*?)\s*$/
        if m and m[2]?
            @file.settings[m[1]] = m[2]
            switch m[1]
                when "token"
                    @file.token = m[2]
                when "display-name"
                    @file.displayname = m[2]
                    @file.remoteAddress = m[2].split(":")[0]
                    @file.basename = path.basename(m[2].split(":")[1])
                when "data"
                    @file.datasize = parseInt(m[2],10)
                    @file.create()
                    @should_parse_data = true

    send: (cmd) ->
        @socket.write cmd+"\n"

    close: ->
        @nconn -= 1
        if @alive and @nconn == 0
            @alive = false
            @send "close"
            @send ""
            @socket.end()


module.exports =
    config:
        launch_at_startup:
            type: 'boolean'
            default: false
        keep_alive:
            type: 'boolean'
            default: false
        port:
            type: 'integer'
            default: 52698,
    server_is_running: false

    activate: (state) ->
        if atom.config.get "remote-atom.launch_at_startup"
            @start_server()
        atom.commands.add 'atom-workspace',
            "remote-atom:start-server", => @start_server()
        atom.commands.add 'atom-workspace',
            "remote-atom:stop-server", => @stop_server()

    deactivate: ->
        @stop_server()

    start_server: (quiet = false) ->
        # stop any existing server
        if @server_is_running
            @stop_server()
            status-message.display "Restarting remote atom server", 2000
        else
            if not quiet
                status-message.display "Starting remote atom server", 2000

        @server = net.createServer (socket) ->
            console.log "[ratom] received connection from #{socket.remoteAddress}"
            session = new Session(socket)

        port = atom.config.get "remote-atom.port"
        @server.on 'listening', (e) =>
            @server_is_running = true
            console.log "[ratom] listening on port #{port}"

        @server.on 'error', (e) =>
            if not quiet
                status-message.display "Unable to start server", 2000
                console.log "[ratom] unable to start server"
            if atom.config.get "remote-atom.keep_alive"
                setTimeout ( =>
                    @start_server(true)
                ), 10000

        @server.on "close", () ->
            console.log "[ratom] stop server"

        @server.listen port, 'localhost'

    stop_server: ->
        status-message.display "Stopping remote atom server", 2000
        if @server_is_running
            @server.close()
            @server_is_running = false
