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
    _id: $$.str

    fields:
        a:
            type: $$.str
        b:
            type: $$.str
            include: false
        c:
            type: $$.str

    reactives:
        d:
            val: ->
                @a() + @c()
        e:
            denorm: true
            include: true
            val: ->
                @b() + 1

J.dm 'FooWatcher', 'fooWatchers',
    _id: $$.str
    reactives:
        getA:
            val: ->
                $$.Foo.fetchOne { a: 1 }
        getOnlyA:
            val: ->
                $$.Foo.fetchOne { a: 1 }, { a: true, _: false }
        getNothing:
            val: ->
                $$.Foo.fetchOne { a: 1 }, { _: false }


J.dm 'Bar', 'bars',
    _id: $$.str

    fields:
        totallySweet:
            type: $$.str

    reactives:
        numberOfFoosWithAEqualTo4:
            type: $$.int
            denorm: true
            val: ->
                $$.Foo.fetch({ a: 4 }).size()


J.dm 'ModelA', 'as',
    _id: $$.str

    fields:
        x:
            type: $$.num

    reactives:
        ar1:
            denorm: true
            val: ->
                @x() + 1

        ar2:
            denorm: true
            val: ->
                @ar1() + 1


J.dm 'ModelB', 'bs',
    _id: $$.str

    fields:
        aId:
            type: $$.str

        y:
            type: $$.num

    reactives:
        br1:
            denorm: true
            val: ->
                @y() + 1

        br2:
            denorm: true
            val: ->
                @br1() + 1

        br3:
            denorm: true
            val: ->
                $$.ModelA.fetchOne(
                    @aId()
                ,
                    fields: ar2: true
                ).ar2() + 1


J.dm 'ModelC', 'cs',
    _id: $$.str

    immutable: true
    fields:
        bId:
            type: $$.str

    reactives:
        cr1:
            denorm: true
            val: ->
                $$.ModelB.fetchOne(
                    @bId()
                ,
                    fields: br3: true
                ).br3() + 1
