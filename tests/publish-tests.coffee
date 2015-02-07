addTest = (testName, testFunc) ->
    return if Meteor.isServer
    Tinytest.addAsync testName, testFunc



addTest "x", (test, onComplete) ->










addTest "xxx", (test, onComplete) ->
    # Do nothing but don't call onComplete
    # so tinytest won't kill our tests