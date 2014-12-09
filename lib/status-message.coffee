#
# Copyright (c) 2014 by Lifted Studios. All Rights Reserved.
#

# Public: Displays a message in the status bar.

class StatusMessage
    # Public: Displays `message` in the status bar.
    #
    # If the status bar does not exist for whatever reason, no message is displayed and no error
    # occurs.
    #
    # message - A {String} containing the message to display.
    constructor: (message) ->
        @statusBar = atom.workspaceView.statusBar
        @span = document.createElement('span')
        atom.workspaceView.statusBar?.appendLeft(@span)
        @setText(message)

    # Public: Removes the message from the status bar.
    remove: ->
        @span.remove()

    # Public: Updates the text of the message.
    #
    # text - A {String} containing the new message to display.
    setText: (text) ->
        @span.textContent = text


module.exports =
    display: (message, timeout) ->
        clearTimeout(@timeout) if @timeout?
        if @message?
            @message.setText(message)
        else
            @message = new StatusMessage(message)

        if timeout?
            clearTimeout(@timeout) if @timeout?
            @timeout = setTimeout(=>
                @message.remove()
                @message = null
            , timeout)
