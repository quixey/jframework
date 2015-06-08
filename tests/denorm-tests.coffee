###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

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
                                newFoos.forEach (foo) ->
                                    if foo._id is fooInstances[0]._id
                                        test.equal foo.e(), 25
                                for j in [0...3]
                                    avs[j].stop()
                                onComplete()
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
    foo = new $$.Foo
    foo.insert()
    fooWatcher = new $$.FooWatcher
    fooWatcher.insert()

    fooWatcher.selectA()
    fooWatcher.selectA_projectA()
    fooWatcher.selectA_projectC()
    fooWatcher.selectA_projectNothing()

    foo.a(5)
    foo.saveAndDenorm()
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'

    foo.b(6)
    foo.c(16)
    foo.saveAndDenorm()
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'
    fooWatcher.selectA()
    fooWatcher.selectA_projectA()
    fooWatcher.selectA_projectC()
    fooWatcher.selectA_projectNothing()

    foo.a(1)
    foo.saveAndDenorm()
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'
    fooWatcher.selectA()
    fooWatcher.selectA_projectA()
    fooWatcher.selectA_projectC()
    fooWatcher.selectA_projectNothing()

    foo.b(7)
    foo.saveAndDenorm()
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'

    foo.c(17)
    foo.saveAndDenorm()
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isFalse _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'
    fooWatcher.selectA()
    fooWatcher.selectA_projectA()
    fooWatcher.selectA_projectC()
    fooWatcher.selectA_projectNothing()

    foo.a(2)
    foo.saveAndDenorm()
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectA'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectC'
    test.isTrue _wasReset 'FooWatcher', fooWatcher._id, 'selectA_projectNothing'
    fooWatcher.selectA()
    fooWatcher.selectA_projectA()
    fooWatcher.selectA_projectC()
    fooWatcher.selectA_projectNothing()


_wasReset = (modelName, instanceId, reactiveName) ->
    modelClass = J.models[modelName]
    reactiveSpec = modelClass.reactiveSpecs[reactiveName]
    J.assert reactiveSpec?.denorm

    doc = modelClass.findOne instanceId, transform: false
    J.assert doc?
    reactiveObj = doc._reactives?[reactiveName]

    console.log 'reactiveObj', reactiveObj, 'wasReset', reactiveObj?.val is undefined and reactiveObj?.ts?

    reactiveObj?.val is undefined and reactiveObj?.ts?


if Meteor.isClient then Tinytest.addAsync "_lastTest3", (test, onComplete) ->
    setTimeout(
        -> onComplete()
        1000
    )

