addTest = (testName, testFunc) ->
    return if Meteor.isServer
    Tinytest.addAsync testName, (test, onComplete) ->
        testFunc test, onComplete

makeId = ->
    "#{Math.floor 10000 * Math.random()}"


addTest "AutoVar - set fetchInProgress when a dependency is setting fetchInProgress", (test, onComplete) ->
    randomId = new ReactiveVar makeId()

    a = J.AutoVar(
        'a'
        ->
            console.log 'compute a'
            foo = $$.Foo.fetchOne randomId.get()
            console.log 'a got', foo
            randomId.get()
    )
    b = J.AutoVar(
        'b'
        ->
            console.log 'run b'
            ret = a.get()
            console.log 'b got', ret
            ret
    )
    c = J.AutoVar(
        'c'
        ->
            console.log 'run c'
            ret = b.get()
            console.log 'c got', ret
            ret
    )

    dRunCount = new ReactiveVar 0
    d = J.AutoVar(
        'd'
        ->
            console.log 'run d'
            drc = Tracker.nonreactive -> dRunCount.get() + 1
            dRunCount.set drc
            console.log 'd2', drc
            test.isTrue c.get()?
            console.log 'd3'
            null
        true
    )
    eRunCount = new ReactiveVar 0
    e = J.AutoVar(
        'e'
        ->
            console.log 'run e'
            eRunCount.set Tracker.nonreactive -> eRunCount.get() + 1
            console.log 'e2'
            test.isTrue c.get()?
            console.log 'e3'
            null
        true
    )

    watcher = J.AutoVar(
        'watcher'
        -> [dRunCount.get(), eRunCount.get()]
        ->
            console.log 'run watcher', dRunCount.get(), eRunCount.get()
            if dRunCount.get() is 2 and eRunCount.get() is 2
                randomId.set makeId()
                console.log "e is", e.get()
                test.isTrue false, "Shouldn't be at this point"
            else if dRunCount.get() is 3 and eRunCount.get() is 3
                a.stop()
                b.stop()
                c.stop()
                d.stop()
                e.stop()
                watcher.stop()
                onComplete()
            null
    )




addTest "Fetching - throw out of AutoVar valueFunc when missing fetch data", (test, onComplete) ->
    count1 = 0
    count2 = 0
    count3 = 0
    a = J.AutoVar(
        ->
            count1 += 1
            if count1 is 5 then crash
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

addTest "Fetching - Don't call AutoVar.onChange until data is ready", (test, onComplete) ->
    completeCount = 0
    a = J.AutoVar(
        -> $$.Foo.fetchOne()
        (oldFoo, newFoo) ->
            test.isTrue newFoo isnt undefined
            a.stop()
            completeCount += 1
            if completeCount is 2 then onComplete()
    )
    b = J.AutoVar(
        -> $$.Foo.fetchOne({xyz: 'dont find me'})
        (oldFoo, newFoo) ->
            test.isTrue newFoo is null
            b.stop()
            completeCount += 1
            if completeCount is 2 then onComplete()
    )

addTest "Fetching - unsubscribe from data when no computation needs it anymore", (test, onComplete) ->
    a = J.AutoVar(
        ->
            $$.Foo.fetch()
            test.isTrue $$.Foo.findOne()?
            b = J.AutoVar(
                ->
                    $$.Foo.fetch()
                    test.isTrue $$.Foo.findOne()?
                    b.stop()
                    Tracker.afterFlush ->
                        test.isTrue $$.Foo.findOne()?
                        a.stop()
                        Tracker.afterFlush ->
                            setTimeout(
                                ->
                                    test.isFalse $$.Foo.findOne()?
                                    onComplete()
                                1000
                            )
                    null
                true
            )
            null
        true
    )

addTest "AutoVar behavior when losing and regaining data", (test, onComplete) ->
    foo = new $$.Foo _id: makeId()
    count = 0
    foo.insert ->
        selector = J.Dict _id: foo._id

        a = J.AutoVar 'a',
            -> $$.Foo.fetchOne selector
        ,
            (oldFoo, newFoo) ->
                count += 1
                if count is 1
                    test.isUndefined oldFoo
                    test.equal newFoo._id, foo._id
                    selector.setOrAdd 'nonExistentField', 5
                    aVal = a.get()
                    test.isUndefined aVal, "a should be undefined because fetch in progress"
                else
                    test.equal oldFoo._id, foo._id, "should have continuity since before a was undefined"
                    test.equal newFoo, null, "newFoo should be null after fetching nothing"
                    a.stop()
                    onComplete()


addTest "Fetching - detect inserted instance", (test, onComplete) ->
    completeCount = 0
    xCount = 0

    foo = new $$.Foo()
    foo.insert ->
        test.isUndefined $$.Foo.findOne(foo._id), "There shouldn't be a cursor that can detect foo"

        fVar = J.AutoVar(
            -> $$.Foo.fetchOne foo._id
            (oldF, newF) ->
                test.equal newF?._id, foo._id
                fVar.stop()
                completeCount += 1
                if completeCount is 3 then onComplete()
        )
    test.isTrue $$.Foo.findOne(foo._id)?, "Latency compensation isn't working as expected"

    bar = new $$.Foo(_id: makeId())
    barDetector = J.AutoVar(
        -> $$.Foo.fetchOne bar._id
        (oldBar, newBar) ->
            if newBar is null
                bar.insert ->
                    test.isTrue $$.Foo.findOne(bar._id)?, "Bar not found after insertion"
                    completeCount += 1
                    xCount += 1
                    if xCount is 2 then barDetector.stop()
                    if completeCount is 3 then onComplete()
                test.isTrue $$.Foo.findOne(bar._id)?, "Latency compensation isn't working as expected"
                return
            test.isTrue newBar?
            xCount += 1
            completeCount += 1
            if xCount is 2 then barDetector.stop()
            if completeCount is 3 then onComplete()
    )


addTest "_lastTest2", (test, onComplete) ->
    setTimeout(
        -> onComplete()
        1000
    )

