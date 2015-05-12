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
            type: $$.str

    state:
        localValue:
            default: -> @prop.defaultValue() ? ''

    reactives:
        value:
            val: ->
                @prop.value() ? @localValue()
            early: true
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
                    @localValue e.target.value
                    @prop.onChange()? e
            onKeyDown: @prop.onKeyDown()
            onKeyUp: @prop.onKeyUp()