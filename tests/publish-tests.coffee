addTest = (testName, testFunc) ->
    return if Meteor.isServer
    Tinytest.addAsync testName, testFunc

addTest "addDataQueries - basics", (test, onComplete) ->
    Meteor.call '_addDataQueries', J.DATA_SESSION_ID, [
        modelName: 'Foo'
        selector: {}
    ], (error, result) ->
        console.log 'addDataQueries callback: ', error, result
        onComplete()














addTest "xxx", (test, onComplete) ->
    # Do nothing but don't call onComplete
    # so tinytest won't kill our tests