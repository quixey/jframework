addTest = (testName, testFunc) ->
    return
    return if Meteor.isServer
    Tinytest.addAsync testName, (test, onComplete) ->
        testFunc test, onComplete

makeId = ->
    "#{Math.floor 10000 * Math.random()}"

debug = false
log = ->
    if debug
        console.log.apply console, arguments

Tinytest.addAsync "weird problem", (test, onComplete) ->
    if Meteor.isServer
        onComplete()
        return

    console.info "begin weird problem"

    a = J.AutoVar 'a',
        ->
            console.info 1

            tagLists = J.AutoVar 'tagLists',
                ->
                    console.info 2
                    x = $$.Foo.fetchOne()
                    console.info 3
                    al = J.AutoList(
                        ->
                            console.info 4
                            2
                        (key) ->
                            console.trace()
                            console.info 5
                            'three'
                    )
                    console.info 6
                    al.tag = 'al'
                    al

            outerTester = J.AutoVar 'outerTester',
                (ot) ->
                    console.info 7
                    ret = tagLists.get()
                    console.info 8
                    ret

            console.info 9
            outerTester.get()

            ['fake1', 'fake2']


    aVal = a.get()
    test.isUndefined aVal
    console.log 'waiting...'
    setTimeout(
        ->
            console.log 'getting aVal2'
            aVal2 = a.get()
            console.log "got: ", aVal2
            onComplete()
        2000
    )


addTest "AutoVar - AutoList fetching inside", (test, onComplete) ->
    debug = true

    changeCount = 0
    randomId1 = new ReactiveVar makeId()
    randomId2 = new ReactiveVar makeId()
    r = new ReactiveVar 5

    fetcher = J.AutoVar 'fetcher',
        ->
            $$.Foo.fetchOne randomId2.get()
            ['a', 'b', randomId2.get()]


    av = J.AutoVar 'av',
        ->
            $$.Foo.fetch randomId1.get()

            al = fetcher.get().map (x) ->
                innerAl = J.AutoList(
                    -> r.get()
                    (j) ->
                        "#{r.get()}#{x},#{j}"
                )
                innerAl.tag = "innerAl"
                innerAl

            av3 = null
            av2 = J.AutoVar 'av2',
                ->
                    av3 = J.AutoVar 'av3',
                        -> al.get(0).getValues()

            J.List(['x', 'y'])
    ,
        (oldAv, newAv) ->
            changeCount += 1
            console.log 'av onChange', changeCount, oldAv, newAv
            if changeCount is 1
                r.set 8
                randomId1.set makeId()
            else
                fetcher.stop()
                av.stop()
                onComplete()




addTest "AutoVar - AutoDict fetching inside", (test, onComplete) ->
    debug = true
    changeCount = 0

    randomId1 = new ReactiveVar makeId()
    randomId2 = new ReactiveVar makeId()
    randomId3 = new ReactiveVar makeId()

    fetcher = J.AutoVar 'fetcher',
        -> $$.Foo.fetch _id: $ne: randomId2.get()
    fetcher3 = J.AutoVar 'fetcher',
        -> $$.Foo.fetch _id: $ne: randomId3.get()

    a = J.AutoVar 'a',
        ->
            console.groupCollapsed("compute a")
            console.trace()
            console.groupEnd()
            ad = J.AutoDict(
                ->
                    console.groupCollapsed('compute ad keys')
                    console.trace()
                    console.groupEnd()

                    ['k0', 'k1', 'k2']
                (key) ->
                    console.groupCollapsed("compute ad.field", key)
                    console.trace()
                    console.groupEnd()
                    ret = $$.Foo.fetch _id: $ne: randomId1.get()
                    log "ad got", ret
                    null
                true
            )
            ad.tag = 'ad'
            log 'a made ad'

            ad.getFields()

            log 'a got fields'

            lst = fetcher.get().map (v) ->
                console.log 'calculate list element', v
                fetcher3.get()
                ret = [v]
                console.log 'ret', ret
                ret
            log 'a made lst'

            lst

    foos = for x in [5, 6, 7]
        new $$.Foo(
            b: x
        )
    foo.insert() for foo in foos

    b = J.AutoVar 'b',
        ->
            console.groupCollapsed("compute b")
            console.trace()
            console.groupEnd()
            ret = a.get()
            console.log 'got a', ret
            console.log 'ret[0] is', ret.get(0)
            Math.random()
    ,
        (oldB, newB) ->
            changeCount += 1
            console.log 'b onChange', changeCount, oldB, newB
            randomId1.set makeId()
            console.log 1
            randomId2.set makeId()
            console.log 2
            if changeCount is 5
                a.stop()
                b.stop()
                fetcher.stop()
                fetcher3.stop()
                deleteCount = 0
                for foo in foos
                    foo.remove  ->
                        deleteCount += 1
                        if deleteCount is 3
                            onComplete()


addTest "AutoVar - invalidation of contents", (test, onComplete) ->
    randomId = makeId()

    a = J.AutoVar 'a',
        ->
            log 'compute a'
            $$.Foo.fetch randomId
            log 'a after fetch'
            J.AutoDict(
                -> ['k']
                -> 5
            )

    b = J.AutoVar 'b',
        ->
            log 'compute b'
            a.get()
            log 'b got a'
            aObj = a.get().toObj()
            log 'b got a obj:', aObj
            a.stop()
            b.stop()
            onComplete()
            null
    ,
        true



addTest "AutoVar - invalidation propagation during fetch", (test, onComplete) ->
    firstId = makeId()
    currentId = firstId
    idVar = new ReactiveVar currentId

    a = J.AutoVar(
        'a'
        ->
            log 'compute a'
            foo = $$.Foo.fetchOne idVar.get()
            log 'a got', foo
            idVar.get()
    )
    b = J.AutoVar(
        'b'
        ->
            log 'compute b'
            ret = a.get()
            log 'b got', ret
            ret
    )
    c = J.AutoVar(
        'c'
        ->
            log 'compute c'
            ret = b.get()
            log 'c got', ret
            ret
    )

    runCount1 = 0
    watcher1 = J.AutoVar(
        'watcher1'
        ->
            runCount1 += 1
            log 'compute watcher1', runCount1
            cVal = c.get()
            log 'watcher1 got', cVal
            if runCount1 is 1
                test.isTrue false, "w1 should have thrown (1)"
            else if runCount1 is 2
                test.equal cVal, currentId
                idVar.set currentId = makeId()
                log 'Should throw here'
                newCVal = c.get()
                test.isTrue false, "Should have thrown"
                log 'newCVal is', newCVal
            else if runCount1 is 3
                test.isTrue false, "w1 should have thrown (2)"
            else if runCount1 is 4
                test.equal cVal, currentId
                a.stop()
                b.stop()
                c.stop()
            cVal
        (oldCVal, newCVal) ->
            log 'watcher1.onChange', runCount1, oldCVal, newCVal
            if runCount1 is 4
                test.equal oldCVal, undefined
                test.equal newCVal, currentId
                watcher1.stop()
                onComplete()
            else
                test.isTrue false, "Invalid watcher onChange: #{runCount1}, #{oldCVal}, #{newCVal}"
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

