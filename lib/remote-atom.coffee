{CompositeDisposable}  = require 'atom'
net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
status-message = require './status-message'

class FileHandler
    readbytes: 0
    settings: {}

    constructor: (session) ->
        @session = session

    make_tempfile: ()->
        @tempfile = path.join(os.tmpdir(), randomstring(10), @basename)
        console.log "[ratom] create #{@tempfile}"
        dirname = path.dirname(@tempfile)
        mkdirp.sync(dirname)
        @fd = fs.openSync(@tempfile, 'w')

    write: (str) ->
        fs.writeSync(@fd, str)

    open_in_atom: ->
        fs.closeSync @fd
        console.log "[ratom] opening #{@tempfile}"
        # register events
        atom.workspace.open(@tempfile, activatePane:true).then (editor) =>
            @handle_connection(editor)

    handle_connection: (editor) ->
        atom.focus()
        buffer = editor.getBuffer()
        @subscriptions = new CompositeDisposable
        @subscriptions.add buffer.onDidSave(@save)
        @subscriptions.add buffer.onDidDestroy(@close)

    save: =>
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

    close: =>
        console.log "[ratom] closing #{path.basename @tempfile}"
        @session.close()
        @subscriptions.dispose()

class Session
    should_parse_data: false
    nconn: 0

    constructor: (socket) ->
        @socket = socket
        @alive = true
        socket.on "data", (chunk) =>
            @parse_chunk(chunk)
        socket.on "close", =>
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
            @prase_data(line)
        else if line.match /open\n/
            @fh = new FileHandler(@)
            @nconn += 1
        else
            @prase_setting(line)

    prase_data: (line) ->
        if @fh.readbytes < @fh.datasize
            @fh.readbytes += Buffer.byteLength(line)
            # remove trailing newline if necessary
            if @fh.readbytes == @fh.datasize + 1 and line.slice(-1) is "\n"
                line = line.slice(0, -1)
            @fh.write(line)
        if @fh.readbytes >= @fh.datasize
            @should_parse_data = false
            @fh.open_in_atom()

    prase_setting: (line) ->
        m = line.match /([a-z\-]+?)\s*:\s*(.*?)\s*$/
        if m and m[2]?
            @fh.settings[m[1]] = m[2]
            switch m[1]
                when "token"
                    @fh.token = m[2]
                when "display-name"
                    @fh.displayname = m[2]
                    @fh.remoteAddress = m[2].split(":")[0]
                    @fh.basename = path.basename(m[2].split(":")[1])
                when "data"
                    @fh.datasize = parseInt(m[2],10)
                    @fh.make_tempfile()
                    @should_parse_data = true

    send: (cmd) ->
        @socket.write cmd+"\n"

    close: ->
        @nconn -= 1
        console.log @nconn
        if @alive and @nconn == 0
            @online = false
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
            session.send("Atom "+atom.getVersion())

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
            @online = false
