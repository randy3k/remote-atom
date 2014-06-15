net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
{Subscriber} = require 'emissary'


class Session
    Subscriber.includeInto(this)
    should_parse_data: false
    readbytes: 0
    settings: {}

    constructor: (socket) ->
        @socket = socket
        @remoteAddress = socket.remoteAddress
        socket.on "readable", =>
            chunk = socket.read()
            @parse_chunk(chunk)

    make_tempfile: ()->
        @tempfile = path.join(os.tmpdir(), randomstring(20), @remoteAddress, @token)
        console.log "[ratom] create #{@tempfile}"
        dirname = path.dirname(@tempfile)
        mkdirp.sync(dirname)
        @fd = fs.openSync(@tempfile, 'w')

    parse_chunk: (chunk) ->
        if chunk
            chunk = chunk.toString("utf8").replace /\s$/, ""
            lines = chunk.split "\n"
            for line in lines
                    @parse_line(line)

    parse_line: (line) ->
        if @should_parse_data
            if @readbytes == @datasize and line is "."
                    @should_parse_data = false
                    fs.closeSync @fd
                    @open_in_atom()
            else
                    @readbytes += Buffer.byteLength(line)
                    if @readbytes < @datasize
                            @readbytes += 1
                            line = line + "\n"
                    fs.writeSync(@fd, line)
        else
            m = line.match /([a-z\-]+?)\s*:\s*(.*)/
            if m and m[2]?
                @settings[m[1]] = m[2]
                switch m[1]
                    when "token"
                        @token = m[2]
                        @make_tempfile()
                    when "data"
                        @datasize = parseInt(m[2],10)
                        @should_parse_data = true


    open_in_atom: ->
        console.log "[ratom] opening #{@tempfile}"
        # register events
        atom.workspace.open(@tempfile).then (editor) =>
            @handle_connection(editor)


    handle_connection: (editor) ->
        buffer = editor.getBuffer()
        @subscribe buffer, 'saved', () => @save()
        @subscribe buffer, 'destroyed', =>
            @unsubscribe(buffer)
            if @socket?
                @close()

    send: (cmd) ->
        @socket.write cmd+"\n"

    save: ->
        console.log "[ratom] saving #{path.basename @tempfile} to #{@remoteAddress}"
        @send "save"
        @send "token:#{@token}"
        data = fs.readFileSync(@tempfile)
        @send "data:" + Buffer.byteLength(data)
        @socket.write data
        @send ""

    close: ->
        @send "close"
        @send ""
        @socket.end()


module.exports =
    configDefaults:{
        Port: 52698
    }
    activate: (state) ->
        @startserver()


    startserver: ->
        @server = net.createServer (socket) ->
            console.log "[ratom] received connection from #{socket.remoteAddress}"
            session = new Session(socket)
            session.send("Atom "+atom.getVersion())

        port = atom.config.get "remote-atom.Port"
        @server.on 'listening', (e) ->
            console.log "[ratom] listening on port #{port}"
        @server.on 'error', (e) ->
            console.log "[ratom] unable to start server"
        @server.on "close", () ->
            console.log "[ratom] stop server"
        @server.listen port, 'localhost'


    deactivate: ->
        @server.close()
