addTest = (testName, testFunc) ->
    return if Meteor.isServer
    Tinytest.addAsync testName, testFunc



addTest "Fetching - throw out off AutoVar valueFunc when missing fetch data", (test, onComplete) ->
    count1 = 0
    count2 = 0
    count3 = 0
    a = J.AutoVar(
        ->
            count1 += 1
            smallFoos = $$.Foo.fetch b: $lte: 3
            count2 += 1
            mediumFoos = $$.Foo.fetch b: $lte: 7
            count3 += 1
            largeFoos = $$.Foo.fetch b: $lte: 10
            test.equal count1, 4
            test.equal count2, 3
            test.equal count3, 2
            a.stop()
            onComplete()
            null
        true
    )


addTest "Fetching - unsubscribe from data when no computation needs it anymore", (test, onComplete) ->
    foo = new $$.Foo b: 12
    foo.insert()
    fVar = J.AutoVar(
        -> $$.Foo.fetchOne foo._id
        (oldF, newF) ->
            if newF?._id is foo._id
                fVar.stop()
                onComplete()
    )





addTest "xxx", (test, onComplete) ->
    # Do nothing but don't call onComplete
    # so tinytest won't kill our tests