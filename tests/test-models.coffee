###
    Model definitions for tests to use.
    # FIXME: Use a different test database for these
###

J.dm 'Foo', 'foos',
    _id: $$.string

    fields:
        a: $$.string
        b: $$.string
        c: $$.string