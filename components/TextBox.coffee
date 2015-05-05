###
    TextBox wraps text inputs. Features:
    * Don't mess up the cursor position when editing a Controlled Component
      (i.e. setting prop.value)
###


J.dc 'TextBox',
    props:
        defaultValue:
            type: $$.str
        enabled:
            default: true
        onChange:
            type: $$.func
        onKeyDown:
            type: $$.func
        onKeyUp:
            type: $$.func
        placeholder:
            type: $$.str
        style:
            type: $$.obj
            default: J.Dict()
        value:
            doc: """
                Can be a string or a reactive expression. If set,
                the component behavior is that of a Controlled Component
                just like React's native textbox.
            """
            type: $$.var

    state:
        _refreshOnValueChange:
            default: true

        localValue:
            default: -> @prop.value() ? @prop.defaultValue() ? ''

    reactives:
        value:
            val: ->
                if @prop.value()?
                    if _.isFunction @prop.value()
                        @prop.value()()
                    else if _.isString @prop.value()
                        @prop.value()
                    else
                        throw new Error "Invalid prop.value for #{@toString()}: #{@prop.value()}"
                else
                    @localValue()
            onChange: (oldValue, newValue) ->
                @afterRender => @_refreshText()


    _refreshText: ->
        inpText = @refs.inpText.getDOMNode()

        if inpText.value isnt @value()
            # Try to keep the cursor in the same place, even
            # though in Controlled Component mode there
            # may have been enough of a transformation in
            # @prop.value that it doesn't make sense.
            oldValue = inpText.value
            oldPos = inpText.selectionStart

            inpText.value = @value()

            if @value().length >= oldValue.length
                newPos = oldPos
            else
                newPos = Math.max 0, oldPos - (oldValue.length - @value().length)

            inpText.selectionStart = newPos
            inpText.selectionEnd = newPos

    focus: ->
        @afterRender =>
            @refs.inpText.getDOMNode().focus()
            J.util.moveCursorToEnd @refs.inpText.getDOMNode()


    render: ->
        $$ ('input'),
            ref: 'inpText',
            type: 'text'
            disabled: not @prop.enabled()
            placeholder: @prop.placeholder()
            style: _.extend {},
                @prop.style().toObj()
            onChange: (e) =>
                if @prop.value()?
                    # Controlled Component mode
                    @prop.onChange()? e
                    @afterRender => @_refreshText()
                else
                    @value e.target.value
                    @prop.onChange()? e
            onKeyDown: @prop.onKeyDown()
            onKeyUp: @prop.onKeyUp()