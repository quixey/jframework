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
        type: $$.str

    fields:
        a:
            type: $$.str
        b:
            type: $$.str
        c:
            type: $$.str

    reactives:
        d:
            val: ->
                @a() + @c()


J.dm 'Bar', 'bars',
    _id:
        type: $$.str

    fields:
        totallySweet:
            type: $$.str

    reactives:
        numberOfFoosWithAEqualTo4:
            type: $$.int
            denorm: true
            val: ->
                $$.Foo.fetch({ a: 4 }).size()
