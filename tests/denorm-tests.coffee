# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


Tinytest.add 'QuerySpec merging', (test) ->
    testEqual = (a, b) ->
        test.equal EJSON.stringify(a), EJSON.stringify(b)

    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
    ,
        modelName: 'Bar'
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
        ,
            modelName: 'Foo'
            selector:
                a: 5
        )
        (
            modelName: 'Foo'
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                a: 6
        ,
            modelName: 'Foo'
            selector:
                a: 5
        )
        (
            modelName: 'Foo'
            selector:
                a: $in: [5, 6]
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                a: 6
                b: 7
                c: 8
        ,
            modelName: 'Foo'
            selector:
                a: 5
                b: 7
                c: 8
        )
        (
            modelName: 'Foo'
            selector:
                a: $in: [5, 6]
                b: 7
                c: 8
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            a: 6
            b: 7
            c: 8
    ,
        modelName: 'Foo'
        selector:
            a: 5
            b: 7
            c: 9
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [5, 7]
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 5, 7, 8]
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            a: 5
            b: 10
    ,
        modelName: 'Foo'
        selector:
            a: 6
            b: $in: [10, 11]
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            'd.x': true
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [5, 7]
        fields:
            _: false
            'd.x': true
            'd.y': true
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            'd.x': true
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [5, 7]
        fields:
            _: false
            d: true
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true

    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
        fields:
            _: false
            a: true
            'd.y': true
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true

        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: -1
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                d: -1
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: 1
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: 1
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
        fields:
            _: false
            a: true
            d: true
        limit: 10
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                d: true
            limit: 20
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                d: true
            limit: 20
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            d: true
        limit: 5
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x.y': true
                'd.x.z': true
            limit: 5
        )
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x.y': true
            'd.x.z': true
        sort:
            a: -1
        limit: 5
    )


Tinytest.add 'isSelectorCovered', (test, onComplete) ->
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
            a: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
            a: 5
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            $or: [a: 5]
            _id: $in: ["abc", "cde", "def"]
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
    ,
        modelName: 'Foo'
        selector:
            a: 3
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
    ,
        modelName: 'Foo'
        selector:
            a: 3
        modelName: 'Foo'
        selector:
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
        sort:
            a: -1
            b: 1
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
        limit: 100
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
        limit: 100
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 1
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
            a: 5
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
            a: $in: [3, 5, 7]
    )




Tinytest.add 'isQsCovered', (test, onComplete) ->
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["aaa", "abc"]
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
        fields:
            d: true
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
        fields:
            e: true
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
    ,
        modelName: 'Foo'
        fields:
            a: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            _: false
    ,
        modelName: 'Foo'
        fields:
            a: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            e: false
    ,
        modelName: 'Foo'
        fields:
            d: false
            e: false
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            d: false
    ,
        modelName: 'Foo'
        fields:
            d: false
            e: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x': true
    ,
        modelName: 'Foo'
        fields:
            d: true
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x': true
    ,
        modelName: 'Foo'
        fields:
            'd.y': true
            'd.z': true
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x.y.z': true
            'd.x.z.a': true
    ,
        modelName: 'Foo'
        fields:
            'd.x.x': true
            'd.x.y': true
            'd.x.z': true
    )




if Meteor.isClient then Tinytest.addAsync 'Subfield selector bookkeeping', (test, onComplete) ->
    c = new $$.ModelC
        d:
            f:
                "g.h*DOT*i":
                    j: 5
                    k: 6
            m:
                n: 7
                'p.q':
                    'r**DOT**s': 8
                    t: 9

    c.insert ->
        a = J.AutoVar(
            'a'

            ->
                $$.ModelC.fetchOne(
                    c._id
                    fields:
                        _: false
                        'd.m': true
                ).d()

            (__, d) ->
                console.log 'onChange', __, d?.toObj()

                test.isUndefined d.get('f')
                test.equal d.m().toObj(),
                    n: 7
                    'p.q':
                        'r**DOT**s': 8
                        t: 9

                # Delay to make sure that accessing .d() didn't
                # register a new dependency on the whole d object
                Meteor.setTimeout(
                    ->
                        a.stop()
                        onComplete()
                    500
                )
        )


Tinytest.add 'QuerySpec canonicalization', (test) ->
    c = (selector) -> J.fetching._getCanonicalSelector selector
    testEqual = (a, b) ->
        test.equal EJSON.stringify(a), EJSON.stringify(b)

    testEqual c(undefined), undefined
    testEqual c('123x'), _id: $in: ['123x']
    testEqual c(_id: 'abc'), _id: $in: ['abc']

    testEqual(
        c(
            b: $in: [6, 4, 3, 10]
            _id: $in: [6, 4, 3, 10]
            a: [6, 4, 3, 10]
        )
        (
            _id: $in: [3, 4, 6, 10]
            a: [6, 4, 3, 10]
            b: $in: [3, 4, 6, 10]
        )
    )

    testEqual(
        c(
            b: [
                c:
                    e: 5
                    d: 6
            ]
            $or: [
                'a.b':
                    e: 5
                    d: 6
            ,
                C:
                    $elemMatch:
                        h: 6
                        g: 5
            ]
        )
        (
            $or: [
                C:
                    $elemMatch:
                        g: 5
                        h: 6
            ,
                'a.b':
                    e: 5
                    d: 6
            ]
            b: [
                c:
                    e: 5
                    d: 6
            ]
        )
    )

    testEqual(
        c(
            b:
                $eq:
                    c: 6
                    b: 5
            a:
                $elemMatch:
                    c: 6
                    b: 5
        )
        (
            a:
                $elemMatch:
                    b: 5
                    c: 6
            b:
                $eq:
                    c: 6
                    b: 5
        )
    )


Tinytest.add 'escapeSubDoc', (test) ->
    d = "a.b":
        c:
            "d*DOT*e*DOT*f.g":
                "h.i.j": "k*DOT*.m.n"
        d: [
            "p"
        ,
            q: "r.s"
        ,
            "t.u**DOT**v": "v.w": "x*DOT*y"
        ]
    d2 = "a*DOT*b":
        c:
            "d**DOT**e**DOT**f*DOT*g":
                "h*DOT*i*DOT*j": "k*DOT*.m.n"
        d: [
            "p"
        ,
            q: "r.s"
        ,
            "t*DOT*u***DOT***v": "v*DOT*w": "x*DOT*y"
        ]

    test.equal J.Model._getEscapedSubdoc(d), d2
    test.equal J.Model._getUnescapedSubdoc(d2), d


if Meteor.isServer then Tinytest.add "resetWatchers 1", (test) ->
    $$.ModelA.remove {}
    $$.ModelB.remove {}
    $$.ModelC.remove {}

    a = new $$.ModelA(
        _id: 'aaa'
        x: 5
    )
    a.save()

    b = new $$.ModelB(
        _id: 'bbb'
        aId: 'aaa'
        y: 60
    )
    b.save()
    b2 = new $$.ModelB(
        _id: 'bbb2'
        aId: 'aaa'
        y: 70
    )
    b2.save()

    c = new $$.ModelC(
        bId: 'bbb'
    )
    c.save()

    test.equal b.br3(), 8



if Meteor.isClient then Tinytest.addAsync "Denorm with overlapping cursors", (test, onComplete) ->
    fooDocs = [
        a: 10
        b: 20
        c: 30
    ,
        a: 100
        b: 200
        c: 300
    ,
        a: 1000
        b: 2000
        c: 3000
    ]
    fooInstances = (new $$.Foo doc for doc in fooDocs)
    fooInstance.save() for fooInstance in fooInstances

    avs =
        for i in [0...3]
            do (i) ->
                J.AutoVar(
                    ->
                        foos = $$.Foo.fetch(
                            _id:
                                $ne: 'x' # Just to throw off smart ID merging
                                $in: (fooInstance._id for fooInstance in fooInstances)
                            a: $gt: i
                        )
                    (oldFoos, newFoos) ->
                        return unless i is 0

                        if newFoos.size() is 3
                            console.log 'mutating b to 24'
                            fooInstances[0].b 24
                            fooInstances[0].save ->
                                # Wait for e to get denormalized
                                setTimeout(
                                    ->
                                        newFoos.forEach (foo) ->
                                            if foo._id is fooInstances[0]._id
                                                test.equal foo.e(), 25
                                        for j in [0...3]
                                            avs[j].stop()
                                        onComplete()
                                    1000
                                )
                )


if Meteor.isClient then Tinytest.addAsync "Field inclusion", (test, onComplete) ->
    foo = new $$.Foo(
        a: 1
        b: 2
        c: 3
    )

    projection = J.Dict()

    foo.insert ->
        x = 0
        fooWatcher = J.AutoVar(
            'fooWatcher'
            -> J.util.withoutUndefined $$.Foo.fetchOne(foo._id, fields: projection).toDoc()
            (__, fooDoc) ->
                console.log 'fooDoc: ', fooDoc.toObj()
                switch x
                    when 0
                        test.equal fooDoc.a(), 1
                        test.isUndefined fooDoc.get('b')
                        test.equal fooDoc.c(), 3
                        foo.c 4
                        foo.save()
                    when 1
                        test.equal fooDoc.a(), 1
                        test.equal fooDoc.b(), 2 # Latency compensation
                        test.equal fooDoc.c(), 4
                    when 2
                        test.equal fooDoc.a(), 1
                        test.isUndefined fooDoc.get('b')
                        test.equal fooDoc.c(), 4
                        projection.setOrAdd 'b', true
                    when 3
                        test.equal fooDoc.a(), 1
                        test.equal fooDoc.b(), 2
                        test.equal fooDoc.c(), 4
                        fooWatcher.stop()
                        onComplete()

                x += 1
        )

if Meteor.isClient then Tinytest.addAsync "isQueryReady", (test, onComplete) ->
    foo = new $$.Foo(
        a: x: 'y'
        c: 10
    )

    projection = J.Dict
        _: false
        c: true

    foo.insert ->
        x = 0
        fooWatcher = J.AutoVar(
            'fooWatcher'
            ->
                attachedFoo = $$.Foo.fetchOne foo._id, fields: projection

                isReady = (projection) ->
                    J.fetching.isQueryReady
                        modelName: 'Foo'
                        selector: foo._id
                        fields: projection
                        sort: undefined
                        limit: 1
                        skip: undefined

                switch x
                    when 0
                        test.isTrue isReady
                            _: false
                            c: true
                        projection.setOrAdd 'c', false
                        projection.setOrAdd 'a', true
                        test.isTrue isReady
                            _: false
                            c: true
                        test.isFalse isReady
                            _: false
                            a: true

                    when 1
                        test.isFalse isReady
                            _: false
                            c: true
                        projection.setOrAdd 'b', true
                    when 2
                        test.isTrue isReady
                            a: false
                            b: true
                            c: false
                            e: false
                        test.isTrue isReady
                            _: false
                            b: true
                        fooWatcher.stop()
                        onComplete()

                x += 1
            true
        )

if Meteor.isClient then Tinytest.addAsync "isQueryReady 2", (test, onComplete) ->
    foo = new $$.Foo(
        a: [5, 6]
        c: x: 7
    )

    projection = J.Dict
        _: false
        a: true
        c: true

    foo.insert ->
        x = 0
        fooWatcher = J.AutoVar(
            'fooWatcher'
            ->
                attachedFoo = $$.Foo.fetchOne foo._id, fields: projection

                isReady = (projection) ->
                    J.fetching.isQueryReady
                        modelName: 'Foo'
                        selector: foo._id
                        fields: projection
                        sort: undefined
                        limit: 1
                        skip: undefined

                switch x
                    when 0
                        test.isTrue isReady
                            c: false
                            e: false
                        fooWatcher.stop()
                        onComplete()

                x += 1
            true
        )


if Meteor.isServer then Tinytest.add "Server-side denormalization - A -> B", (test) ->
    bar = new $$.Bar
    bar.insert()

    foo = new $$.Foo
    foo.insert()

    beforeCount = bar.numberOfFoosWithAEqualTo4()
    foo.a(4)
    foo.save()
    test.equal bar.numberOfFoosWithAEqualTo4(), beforeCount + 1, "should have 1 more Foo instance with a == 4"

    foo.remove()
    bar.remove()


if Meteor.isClient then Tinytest.addAsync "Client-side denormalization - A -> B", (test, onComplete) ->
    foo = new $$.Foo
    foo.insert()

    bar = new $$.Bar

    bar.save (barId) ->
        attachedBar = J.AutoVar -> $$.Bar.fetchOne barId

        count = J.AutoVar(
            'count'
            ->
                attachedBar.get().numberOfFoosWithAEqualTo4()
            (oldCount, newCount) ->
                console.log 'onchange', oldCount, newCount
                if oldCount is undefined
                    foo.a(4)
                    foo.save()
                else
                    test.equal newCount, oldCount + 1, "should have 1 more Foo instance with a == 4"
                    count.stop()
                    attachedBar.stop()
                    foo.remove()
                    bar.remove()
                    _.defer onComplete
        )

if Meteor.isServer then Tinytest.add "ResetWatchers - be smart about projections", (test) ->
    # Accesses each reactive of a `fooWatcher`
    # to make sure that it starts watching `foo`.
    touchFooWatcher = (fw) ->
        fw.get reactiveName for reactiveName, reactiveSpec of $$.FooWatcher.reactiveSpecs

    # Check that a `fooWatcher` resets the
    # watchers it should and does not reset
    # the ones it should not.
    #
    #     # Input: (
    #     #   `FooWatcher` instance,
    #     #   array of watchers that should be reset
    #     # )
    #        # `foo`s with `foo.a == 1`:
    #        'selectA',                 # gets the `foo.a` and `foo.c` fields.
    #        'selectA_projectA',        # gets only the `foo.a` field.
    #        'selectA_projectC',        # gets only the `foo.c` field.
    #        'selectA_projectNothing',  # gets none of the fields.
    #
    #        # `foo`s with `foo.b in [100, 101]`:
    #        'selectB',                 # gets the `foo.a` and `foo.c` fields.
    #        'selectB_projectB',        # gets only the `foo.b` fields.
    #
    #        # `foo`s with `foo.c in [100, 101]`:
    #        'selectC'                  # gets the `foo.a` and `foo.c` fields.
    checkFooWatcherReset = (fw, reset) ->
        for reactiveName of $$.FooWatcher.reactiveSpecs
            if reactiveName in reset
                test.isTrue _wasReset('FooWatcher', fw._id, reactiveName),
                    "Should have reset <FooWatcher ##{fw._id}>.#{reactiveName}"
            else
                test.isFalse _wasReset('FooWatcher', fw._id, reactiveName),
                    "Should NOT have reset <FooWatcher ##{fw._id}>.#{reactiveName}"


    foo = new $$.Foo
    foo.insert()
    fooWatcher = new $$.FooWatcher
    fooWatcher.insert()
    touchFooWatcher fooWatcher

    foo.a(5)
    foo.saveAndDenorm()
    # Since we set `foo.a(5)` and `fooWatcher`
    # only cares if `foo.a == 1`, no watchers
    # should be reset.
    checkFooWatcherReset fooWatcher, []

    foo.b(6)
    foo.c(16)
    foo.saveAndDenorm()
    # `foo.b` and foo.c` are irrelevant.
    checkFooWatcherReset fooWatcher, []
    touchFooWatcher fooWatcher

    foo.a(1)
    foo.saveAndDenorm()
    # We set `foo.a(1)`. This should
    # reset all `selectA` watchers on `fooWatcher`.
    checkFooWatcherReset fooWatcher, [
        'selectA',
        'selectA_projectA',
        'selectA_projectC',
        'selectA_projectNothing'
    ]
    touchFooWatcher fooWatcher

    foo.b(7)
    foo.saveAndDenorm()
    # `foo.b` is not a default fetched field,
    # so it should not affect `fooWatcher`.
    checkFooWatcherReset fooWatcher, []

    foo.c(17)
    foo.saveAndDenorm()
    # `foo.c` is a default fetched field,
    # so both `selectA` and `selectA_projectC`
    # should reset.
    checkFooWatcherReset fooWatcher, [
        'selectA',
        'selectA_projectC'
    ]
    touchFooWatcher fooWatcher

    foo.a(2)
    foo.saveAndDenorm()
    # We change `foo.a` from the matching value
    # `1` to `2`. Since `fooWatcher` has starting
    # watching `foo`, it should reset all selectA
    # watchers to stop watching.
    checkFooWatcherReset fooWatcher, [
        'selectA',
        'selectA_projectA',
        'selectA_projectC',
        'selectA_projectNothing'
    ]
    touchFooWatcher fooWatcher

    foo.b(100)
    foo.saveAndDenorm()
    # `100` is a watched `foo.b` value.
    # The `selectB` watchers should reset.
    checkFooWatcherReset fooWatcher, [
        'selectB',
        'selectB_projectB'
    ]
    touchFooWatcher fooWatcher

    foo.b(101)
    foo.saveAndDenorm()
    # `101` is the other watched value.
    checkFooWatcherReset fooWatcher, [
        'selectB',
        'selectB_projectB'
    ]
    touchFooWatcher fooWatcher

    foo.b(102)
    foo.saveAndDenorm()
    # `102` is not watched. The `selectB`
    # watchers should reset to unwatch.
    checkFooWatcherReset fooWatcher, [
        'selectB',
        'selectB_projectB'
    ]
    touchFooWatcher fooWatcher

    foo.b(103)
    foo.saveAndDenorm()
    # Changing `foo.b` to another unwatched
    # value should not reset any watchers.
    checkFooWatcherReset fooWatcher, []
    touchFooWatcher fooWatcher

    foo.c(100)
    foo.saveAndDenorm()
    # `foo.c` should now be watched by `selectC`.
    checkFooWatcherReset fooWatcher, ['selectC']
    touchFooWatcher fooWatcher


_wasReset = (modelName, instanceId, reactiveName) ->
    modelClass = J.models[modelName]
    reactiveSpec = modelClass.reactiveSpecs[reactiveName]
    J.assert reactiveSpec?.denorm

    doc = modelClass.findOne instanceId, transform: false
    J.assert doc?
    reactiveObj = doc._reactives?[reactiveName]

    console.log 'reactiveObj', reactiveObj, 'wasReset', reactiveObj?.val is undefined and reactiveObj?.ts?

    reactiveObj?.dirty isnt false


if Meteor.isClient then Tinytest.addAsync "_lastTest3", (test, onComplete) ->
    setTimeout(
        -> onComplete()
        1000
    )

