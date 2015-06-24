# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.
#

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
                        console.log 0
                        test.equal fooDoc.a(), 1
                        test.isUndefined fooDoc.get('b')
                        test.equal fooDoc.c(), 3
                        foo.c 4
                        foo.save()
                    when 1
                        console.log 1
                        test.equal fooDoc.a(), 1
                        test.equal fooDoc.b(), 2 # Latency compensation
                        test.equal fooDoc.c(), 4
                        console.log 1.5
                    when 2
                        console.log 2
                        test.equal fooDoc.a(), 1
                        test.equal fooDoc.c(), 4
                        projection.setOrAdd 'b', true
                    when 3
                        console.log 3
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
                    J.fetching.isQueryReady J.fetching.makeCanonicalQs
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
                    J.fetching.isQueryReady J.fetching.makeCanonicalQs
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
    setTimeout(
        ->
            test.fail()
            onComplete()
        1
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
        console.log 'gonna check if fw reset', fw._id
        for reactiveName of $$.FooWatcher.reactiveSpecs
            if reactiveName in reset
                test.isTrue _wasReset('FooWatcher', fw._id, reactiveName),
                    "Should have reset <FooWatcher ##{fw._id}>.#{reactiveName}"
            else
                test.isFalse _wasReset('FooWatcher', fw._id, reactiveName),
                    "Should NOT have reset <FooWatcher ##{fw._id}>.#{reactiveName}"

    $$.Foo.remove({})

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
        'selectA_projectAC',
        'selectA_projectA',
        'selectA_projectC',
        'selectA_projectNothing'
    ]
    touchFooWatcher fooWatcher

    foo.b(7)
    foo.saveAndDenorm()
    # `foo.b` is not a default fetched field,
    # so it should not affect `fooWatcher`.
    checkFooWatcherReset fooWatcher, [
    ]

    foo.c(17)
    foo.saveAndDenorm()
    # `foo.c` is a default fetched field,
    # so both `selectA` and `selectA_projectC`
    # should reset.
    checkFooWatcherReset fooWatcher, [
        'selectA_projectAC',
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
        'selectA_projectAC',
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

    # console.log 'reactiveObj', "<#{modelName} #{JSON.stringify instanceId}>.#{reactiveName}
    #    wasReset", reactiveObj?.dirty isnt false, reactiveObj

    reactiveObj?.dirty isnt false


if Meteor.isClient then Tinytest.addAsync "_lastTest3", (test, onComplete) ->
    setTimeout(
        -> onComplete()
        1000
    )

