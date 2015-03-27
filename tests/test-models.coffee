###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


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