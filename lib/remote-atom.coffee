{CompositeDisposable, Point}  = require 'atom'
net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
status-message = require './status-message'

class FileHandler
    constructor: (session) ->
        @session = session
        @settings = {}
        @readbytes = 0
        @ready = false

    set: (index, value) ->
        @settings[index] = value
        if index == "display-name"
            m = value.match /(.*?):(.*)$/
            if m and m[2]?
                @remote_address = value.split(":")[0]
                @basename = path.basename(value.split(":")[1])
            else
                @remote_address = "unknown"
                @basename = value
        else if index == "data"
            @datasize = parseInt(value,10)

    get: (index) ->
        return @settings[index]

    create: ->
        @tempfile = path.join(os.tmpdir(), randomstring(10), @basename)
        console.log "[ratom] create #{@tempfile}"
        dirname = path.dirname(@tempfile)
        mkdirp.sync(dirname)
        @fd = fs.openSync(@tempfile, 'w')

    append: (line) ->
        if @readbytes < @datasize
            @readbytes += Buffer.byteLength(line)
            # remove trailing newline if necessary
            if @readbytes == @datasize + 1 and line.slice(-1) is "\n"
                @readbytes = @datasize
                line = line.slice(0, -1)
            fs.writeSync(@fd, line)
        if @readbytes >= @datasize
            fs.closeSync @fd
            @ready = true

    open: ->
        atom.focus()
        console.log "[ratom] opening #{@tempfile}"
        # register events
        atom.workspace.open(@tempfile, activatePane:true).then (editor) =>
            @handle_connection(editor)

    handle_connection: (editor) ->
        if row = @get("selection")
            row = parseInt(row, 10) - 1
            position = new Point(row, 0)
            editor.scrollToBufferPosition(position, center: true)
            editor.setCursorBufferPosition(position)

        buffer = editor.getBuffer()
        @subscriptions = new CompositeDisposable
        @subscriptions.add buffer.onDidSave =>
            @save()
        @subscriptions.add buffer.onDidDestroy =>
            @close()

    save: ->
        if not @session.alive
            console.log "[ratom] Error saving #{path.basename @tempfile} to #{@remote_address}"
            status-message.display "Error saving #{path.basename @tempfile} to #{@remote_address}", 2000
            return
        console.log "[ratom] saving #{path.basename @tempfile} to #{@remote_address}"
        status-message.display "Saving #{path.basename @tempfile} to #{@remote_address}", 2000
        @session.send "save"
        @session.send "token: #{@settings['token']}"
        data = fs.readFileSync(@tempfile)
        @session.send "data: " + Buffer.byteLength(data)
        @session.send data

    close: ->
        @session.send "close"
        @session.send "token: #{@settings['token']}"
        @session.send ""
        console.log "[ratom] closing #{path.basename @tempfile}"
        @subscriptions.dispose()
        @session.try_end()

class Session
    constructor: (socket) ->
        @should_parse_data = false
        @nconn = 0
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
            @file.append(line)
            if @file.ready
                @should_parse_data = false
                @file.open()
                @file = null

        else if line.match /open\s*$/
            @file = new FileHandler(@)
            @nconn += 1
        else
            @parse_setting(line)

    parse_setting: (line) ->
        m = line.match /([a-z\-]+?)\s*:\s*(.*?)\s*$/
        if m and m[2]?
            @file.set(m[1], m[2])
            if m[1] == "data"
                @file.create()
                @should_parse_data = true

    send: (cmd) ->
        @socket.write cmd+"\n"

    try_end: ->
        @nconn -= 1
        if @alive and @nconn == 0
            @alive = false
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
            console.log "[ratom] received connection from #{socket.remote_address}"
            session = new Session(socket)

        port = atom.config.get "remote-atom.port"
        @server.on 'listening', (e) =>
            @server_is_running = true
            console.log "[ratom] listening on port #{port}"

        @server.on 'error', (e) =>
            if not quiet
                status-message.display "Unable to start server", 2000
                console.log "[ratom] unable to start server"
                console.log "[ratom] #{e}"
            if atom.config.get "remote-atom.keep_alive"
                setTimeout ( =>
                    @start_server(true)
                ), 10000

        @server.on "close", () ->
            console.log "[ratom] stop server"

        @server.listen port, '0.0.0.0'

    stop_server: ->
        status-message.display "Stopping remote atom server", 2000
        if @server_is_running
            @server.close()
            @server_is_running = false
