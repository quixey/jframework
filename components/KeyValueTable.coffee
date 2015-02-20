J.dc 'KeyValueTable',
    props:
        obj:
            type: React.PropTypes.object.isRequired
        keyStyle:
            type: React.PropTypes.object
        sortKeys:
            type: React.PropTypes.bool.isRequired
            default: false


    render: ->
        keys = _.keys @prop.obj()
        if @prop.sortKeys() then keys.sort J.util.compare

        $$ ('table'),
            cellSpacing: 0
            cellPadding: 0

            $$ ('tbody'),
                {}

            for key in keys
                value = @prop.obj()[key]

                $$ ('tr'),
                    key: key

                    $$ ('td'),
                        style:
                            _.extend
                                fontWeight: 'bold'
                                paddingRight: 12
                            ,
                                @prop.keyStyle() ? {}
                        ("#{key}")

                    $$ ('td'),
                        {}

                        if React.isValidElement value
                            value

                        else if J.util.isPlainObject value
                            $$ ('KeyValueTable'),
                                obj: value

                        else
                            ("#{value}")