module.exports =
    display: (text, timeout) ->
        clearTimeout(@timeout) if @timeout?
        @statusBarTile?.destroy()
        statusBar = document.querySelector("status-bar")
        span = document.createElement('span')
        span.textContent = text
        if statusBar?
            @statusBarTile = statusBar.addLeftTile(item: span, priority: 100)

        if timeout?
            clearTimeout(@timeout) if @timeout?
            @timeout = setTimeout(=>
                @statusBarTile?.destroy()
            , timeout)
