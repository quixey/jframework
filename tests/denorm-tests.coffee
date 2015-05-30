###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


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



if Meteor.isServer then Tinytest.add "Server-side denormalization - A -> B", (test) ->
    bar = new $$.Bar

    foo = new $$.Foo
    foo.insert()

    beforeCount = bar.numberOfFoosWithAEqualTo4()
    foo.a(4)
    foo.save()
    test.equal bar.numberOfFoosWithAEqualTo4(), beforeCount + 1, "should have 1 more Foo instance with a == 4"


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


if Meteor.isClient then Tinytest.addAsync "_lastTest3", (test, onComplete) ->
    setTimeout(
        -> onComplete()
        1000
    )

