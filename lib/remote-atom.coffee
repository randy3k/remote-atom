{CompositeDisposable}  = require 'atom'
net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
status-message = require './status-message'

class Session
    should_parse_data: false
    readbytes: 0
    settings: {}

    constructor: (socket) ->
        @socket = socket
        @online = true
        socket.on "data", (chunk) =>
            @parse_chunk(chunk)
        socket.on "close", =>
            @online = false

    make_tempfile: ()->
        @tempfile = path.join(os.tmpdir(), randomstring(10), @basename)
        console.log "[ratom] create #{@tempfile}"
        dirname = path.dirname(@tempfile)
        mkdirp.sync(dirname)
        @fd = fs.openSync(@tempfile, 'w')

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
            if @readbytes >= @datasize and line is ".\n"
                @should_parse_data = false
                fs.closeSync @fd
                @open_in_atom()
            else if @readbytes < @datasize
                @readbytes += Buffer.byteLength(line)
                if @readbytes > @datasize and line.slice(-1) is "\n"
                    line = line.slice(0, -1)
                fs.writeSync(@fd, line)
        else
            m = line.match /([a-z\-]+?)\s*:\s*(.*?)\s*$/
            if m and m[2]?
                @settings[m[1]] = m[2]
                switch m[1]
                    when "token"
                        @token = m[2]
                    when "data"
                        @datasize = parseInt(m[2],10)
                        @should_parse_data = true
                    when "display-name"
                        @displayname = m[2]
                        @remoteAddress = @displayname.split(":")[0]
                        @basename = path.basename(@displayname.split(":")[1])
                        @make_tempfile()

    open_in_atom: ->
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

    send: (cmd) ->
        if @online
            @socket.write cmd+"\n"

    save: =>
        if not @online
            console.log "[ratom] Error saving #{path.basename @tempfile} to #{@remoteAddress}"
            status-message.display "Error saving #{path.basename @tempfile} to #{@remoteAddress}", 2000
            return
        console.log "[ratom] saving #{path.basename @tempfile} to #{@remoteAddress}"
        status-message.display "Saving #{path.basename @tempfile} to #{@remoteAddress}", 2000
        @send "save"
        @send "token: #{@token}"
        data = fs.readFileSync(@tempfile)
        @send "data: " + Buffer.byteLength(data)
        @socket.write data
        @send ""

    close: =>
        console.log "[ratom] closing #{path.basename @tempfile}"
        if @online
            @online = false
            @send "close"
            @send ""
            @socket.end()
        @subscriptions.dispose()


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
    online: false

    activate: (state) ->
        if atom.config.get "remote-atom.launch_at_startup"
            @startserver()
        atom.commands.add 'atom-workspace',
            "remote-atom:start-server", => @startserver()
        atom.commands.add 'atom-workspace',
            "remote-atom:stop-server", => @stopserver()

    deactivate: ->
        @stopserver()

    startserver: (quiet = false) ->
        # stop any existing server
        if @online
            @stopserver()
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
            @online = true
            console.log "[ratom] listening on port #{port}"
        @server.on 'error', (e) =>
            if not quiet
                status-message.display "Unable to start server", 2000
                console.log "[ratom] unable to start server"
            if atom.config.get "remote-atom.keep_alive"
                setTimeout ( =>
                    @startserver(true)
                ), 10000

        @server.on "close", () ->
            console.log "[ratom] stop server"
        @server.listen port, 'localhost'

    stopserver: ->
        status-message.display "Stopping remote atom server", 2000
        if @online
            @server.close()
            @online = false
