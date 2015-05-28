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

Tinytest.add "Denormalization - A -> B", (test) ->
    bar = new $$.Bar
    if Meteor.isServer
        foo = new $$.Foo
        foo.insert()

        beforeCount = bar.numberOfFoosWithAEqualTo4()
        foo.a(4)
        foo.save()
        test.equals bar.numberOfFoosWithAEqualTo4(), beforeCount + 1, "should have 1 more Foo instance with a == 4"
    else
        a = new J.AutoVar -> bar.numberOfFoosWithAEqualTo4()
        foo = new $$.Foo
        foo.insert()

        beforeCount =  a.get()
        foo.a(4)
        foo.save()
        test.equals a.get(), beforeCount + 1, "should have 1 more Foo instance with a == 4"
    foo.remove()

Tinytest.add "Model - static field bindings", (test) ->
    if Meteor.isServer
        foo = new $$.Foo
        a = foo.a
        a()
        foo.a()
        test.equals a(), foo.a()

Tinytest.add "Model - reactive field bindings", (test) ->
    if Meteor.isServer
        bar = new $$.Bar
        n = bar.numberOfFoosWithAEqualTo4
        bar.numberOfFoosWithAEqualTo4()
        n()
        test.equals bar.numberOfFoosWithAEqualTo4(), n()
