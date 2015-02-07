addTest = (testName, testFunc) ->
    return if Meteor.isServer
    Tinytest.addAsync testName, testFunc



addTest "addDataQueries - callback happens after data updates", (test, onComplete) ->
    rid = "#{parseInt 100 * Math.random()}"
    rid2 = "#{parseInt 100 * Math.random()}"
    foo = new $$.Foo _id: rid, b: 4
    bar = new $$.Foo _id: rid2, b: 44
    fooComplete = false
    barComplete = false
    test.isFalse $$.Foo.findOne(rid)?
    test.isFalse $$.Foo.findOne(rid2)?
    foo.insert null, ->
        test.isFalse $$.Foo.findOne(rid)?
        fooComplete = true
        if fooComplete and barComplete then onComplete()
        foo.remove()
    bar.insert null, ->
        test.isTrue $$.Foo.findOne(rid2)?
        barComplete = true
        if fooComplete and barComplete then onComplete()
        bar.remove()










addTest "xxx", (test, onComplete) ->
    # Do nothing but don't call onComplete
    # so tinytest won't kill our tests