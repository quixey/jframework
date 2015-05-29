###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


cleanUp = ->
    if Meteor.isServer
        $$.Foo.fetch().forEach (foo) -> foo.remove()
        $$.Bar.fetch().forEach (bar) -> bar.remove()
    else
        a = new J.AutoVar -> $$.Foo.fetch()
        a.get().forEach (foo) ->
            foo.remove()
        a = new J.AutoVar -> $$.Bar.fetch()
        a.get().forEach (bar) ->
            bar.remove()

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