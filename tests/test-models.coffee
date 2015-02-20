###
    Model definitions for tests to use.
###

J.dm 'Foo', 'foos',
    _id:
        type: $$.string

    fields:
        a:
            type: $$.string
        b:
            type: $$.string
        c:
            type: $$.string

    reactives:
        d:
            val: ->
                @a() + @c()