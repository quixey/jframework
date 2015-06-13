# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


# Model definitions for tests to use.

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

J.dm 'FooWatcher', 'foowatchers',
    _id: $$.str
    reactives:
        selectA:
            denorm: true
            val: ->
                $$.Foo.fetchOne(a: 1)
                null
        selectA_projectA:
            denorm: true
            val: ->
                $$.Foo.fetchOne(
                    a: 1
                ,
                    fields:
                        _: false
                        a: true
                )
                null
        selectA_projectC:
            denorm: true
            val: ->
                $$.Foo.fetchOne(
                    a: 1
                ,
                    fields:
                        _: false
                        c: true
                )
                null
        selectA_projectNothing:
            denorm: true
            val: ->
                $$.Foo.fetchOne(
                    a: 1
                ,
                    fields:
                        _: false
                )
                null

        selectB:
            denorm: true
            val: ->
                $$.Foo.fetchOne b: $in: [100, 101]
                null
        selectB_projectB:
            denorm: true
            val: ->
                $$.Foo.fetchOne(
                    b: $in: [100, 101]
                ,
                    fields:
                        _: false
                        b: true
                )
                null

        selectC:
            denorm: true
            val: ->
                $$.Foo.fetchOne c: $in: [100, 101]
                null


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

    fields:
        bId:
            type: $$.str
        d:
            type: $$.dict

    reactives:
        cr1:
            denorm: true
            val: ->
                return null if @bId() is null
                $$.ModelB.fetchOne(
                    @bId()
                ,
                    fields: br3: true
                ).br3() + 1
