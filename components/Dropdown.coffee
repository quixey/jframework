J.dc 'Dropdown',
    props:
        enabled:
            type: $$.bool
            default: true
        defaultValue:
            type: $$.any
        onChange:
            type: $$.func
        options:
            type: $$.list
            required: true
        style:
            type: $$.dict
            default: J.Dict()
        value:
            type: $$.any

    state:
        localValue:
            type: $$.any
            default: ->
                @prop.defaultValue() ? @prop.options().get(0).value()
            onChange: (oldLocalValue, newLocalValue) ->
                if not @prop.value()?
                    @prop.onChange()? (
                        oldValue: oldLocalValue
                        value: newLocalValue
                    )

    reactives:
        value:
            val: ->
                @prop.value() ? @localValue()


    render: ->
        $$ ('select'),
            disabled: not @prop.enabled()
            value: @value()
            style:
                _.extend {},
                    @prop.style().toObj()
            onChange: (e) =>
                if @prop.value()?
                    # Controlled Component mode
                    @prop.onChange()? (
                        oldValue: @prop.value()
                        value: e.target.value
                    )
                else
                    @localValue e.target.value

            @prop.options().map (option, i) =>
                $$ ('option'),
                    key: option.get('key') ? i
                    value: option.value()
                    disabled: not (option.get('enabled') ? true)
                    (option.content())