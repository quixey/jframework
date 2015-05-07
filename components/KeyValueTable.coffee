###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'KeyValueTable',
    props:
        obj:
            type: $$.dict
            required: true
        keyStyle:
            type: $$.dict
        sortKeys:
            type: $$.bool
            required: true
            default: false


    render: ->
        keys = @prop.obj().getKeys()
        if @prop.sortKeys() then keys.sort J.util.compare

        $$ ('table'),
            cellSpacing: 0
            cellPadding: 0

            $$ ('tbody'),
                {}

            for key in keys
                value = @prop.obj().get(key)

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

                        else if value instanceof J.Dict
                            $$ ('KeyValueTable'),
                                obj: value

                        else
                            ("#{value}")