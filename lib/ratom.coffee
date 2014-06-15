net = require 'net'
fs = require 'fs'
os = require 'os'
path = require 'path'
mkdirp = require 'mkdirp'
randomstring = require './randomstring'
{Subscriber} = require 'emissary'


port = 52698

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

    make_tempfile: (token) ->
        @tempfile = path.join(os.tmpdir(), randomstring(20), @remoteAddress, token)
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
                        @make_tempfile m[2]
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
        @subscribe buffer, 'saved', () => @on_saved()
        @subscribe buffer, 'destroyed', =>
            @unsubscribe(buffer)
            @close()

    on_saved: ->
        console.log "[ratom] saving #{path.basename @tempfile} to #{@remoteAddress}"

    send_command: (cmd) ->
        @socket.write cmd+"\n"

    close: ->
        @send_command "close"
        @send_command ""
        @socket.end()


module.exports =
    activate: (state) ->
        @startserver()

    startserver: ->
        @server = net.createServer (socket) ->
            console.log "[ratom] received connection from #{socket.remoteAddress}"
            session = new Session(socket)
            session.send_command("Atom "+atom.getVersion())

        console.log "[ratom] listening on port #{port}"
        @server.listen port, 'localhost'

    deactivate: ->
