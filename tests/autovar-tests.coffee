Tinytest.addAsync "AutoVar - Control its value's invalidation", (test, onComplete) ->
    ###
        If an AutoVar's value is running its own computation,
        then the AutoVar's computation is the only one
        whose invalidation can invalidate that child's
        computation.
    ###
    al = null
    av = J.AutoVar "av",
        ->
            al = J.AutoList(
                -> 3
                (i) -> 5
            )
            al.tag = "av.al"
            al

    av2 = J.AutoVar "av2",
        -> av.get()

    test.isFalse av.stopped
    test.isFalse av2.stopped
    test.isNull al
    Meteor.defer =>
        test.isNull al

        Tracker.autorun (c) =>
            myAl = av2.get()
            test.isTrue al.isActive(), "al stopped prematurely"
            test.isFalse myAl.stopped, "myAl stopped prematurely"
            av2.stop()

            test.isTrue myAl.isActive()
            test.isFalse av.stopped
            test.isTrue al.isActive()
            av.stop()
            test.isFalse al.isActive()
            test.isFalse myAl.isActive()

            c.stop()

            onComplete()


Tinytest.add "AutoVar - dependency cycle", (test) ->
    firstRun = J.Var true
    runCount = 0

    a = J.AutoVar 'a', ->
        runCount += 1
        if firstRun.get()
            1
        else
            Math.min a.get() + 1, 10

    test.equal a.get(), 1
    firstRun.set false
    if Meteor.isClient then test.throws -> a.get()
    a.stop()


Tinytest.add "AutoVar - invalidation of parent computation", (test) ->
    v = J.Var 5
    b = null
    a = J.AutoVar 'a', ->
        b = J.AutoVar 'b', ->
            v.get()
        b.get()

    test.equal a.get(), 5
    v.set 6
    test.equal a.get(), 6
    Tracker.flush()
    test.equal a.get(), 6

Tinytest.add "AutoVar - invalidation of parent computation 2", (test) ->
    v = J.Var 5
    b = null
    a = J.AutoVar 'a', ->
        b.get()
    b = J.AutoVar 'b', ->
        v.get()
    c = J.AutoVar 'c', ->
        10

    test.equal a.get(), 5
    v.set 6
    test.equal a.get(), 6
    test.equal b.get(), 6
    test.equal c.get(), 10
    Tracker.flush()
    test.equal a.get(), 6
    test.equal b.get(), 6


Tinytest.add "AutoVar - invalidation of parent computation 3", (test) ->
    v = J.Var 5, tag: 'v'

    a = J.AutoVar 'a',
        ->
            c = J.AutoVar 'c', ->
                if v.get() is 6
                    w.get()
                    'v is 6'
                else
                    'v is not 6'

            w = J.AutoVar 'w', -> v.get()

            c.get()
            w.get()
            3

    test.equal a.get(), 3
    v.set 6
    test.equal a.get(), 3
    Tracker.flush()
    test.equal a.get(), 3



Tinytest.add "AutoVar - onchange", (test) ->
    vHist = []
    v = J.Var 5,
        onChange: (oldV, newV) ->
            vHist.push [oldV, newV]

    aHist = []
    a = J.AutoVar('a'
        -> v
        (oldV, newV) ->
            aHist.push [oldV, newV]
    )
    v.set 6
    v.set 'x'
    v.set J.makeValueNotReadyObject()
    test.throws -> v.get()
    test.throws -> a.get()
    v.set 'x'
    v.set J.makeValueNotReadyObject()
    v.set 6
    Tracker.flush()
    test.equal a.get(), 6
    v.set J.makeValueNotReadyObject()
    v.set 7
    Tracker.flush()
    test.equal a.get(), 7
    v.set 7
    v.set 5
    v.set 3
    test.equal vHist, [
        [5, 6]
        [6, 'x']
        ['x', 6]
        [6, 7]
    ]
    test.equal aHist, [
        [undefined, 6]
        [6, 7]
    ]
    vHist = []
    aHist = []
    Tracker.flush()
    goodVHist = [
        [7, 5]
        [5, 3]
    ]
    goodAHist = [
        [7, 3]
    ]
    test.equal vHist, goodVHist
    test.equal aHist, goodAHist
    a.stop()
    test.equal aHist, goodAHist

Tinytest.add "AutoVar - basics 1", (test) ->
    x = new J.Var 5
    xPlusOne = J.AutoVar -> x.get() + 1
    test.equal xPlusOne.get(), 6
    x.set 10
    test.equal xPlusOne.get(), 11
    Tracker.flush()
    test.equal xPlusOne.get(), 11

Tinytest.add "AutoVar - be lazy when no one is looking", (test) ->
    x = new J.Var 5
    runCount = 0
    xPlusOne = J.AutoVar ->
        runCount += 1
        x.get() + 1
    test.equal runCount, 0
    x.set 10
    test.equal runCount, 0
    Tracker.flush()
    test.equal runCount, 0
    test.equal xPlusOne.get(), 11
    test.equal runCount, 1, "fail 1"
    Tracker.flush()
    test.equal runCount, 1, "fail 1.5"
    test.equal xPlusOne.get(), 11
    test.equal runCount, 1, "fail 2"
    x.set 20
    test.equal runCount, 1, "fail 3"
    Tracker.flush()
    x.set 30
    test.equal runCount, 2, "fail 4"
    Tracker.flush()
    x.set 40
    test.equal runCount, 3, "fail 5"
    Tracker.flush()
    test.equal runCount, 4, "fail 6"
    test.equal xPlusOne.get(), 41
    test.equal runCount, 4
    test.equal xPlusOne.get(), 41
    test.equal runCount, 4


Tinytest.add "AutoVar - don't be lazy if someone is looking", (test) ->
    x = new J.Var 5
    runCount = 0
    xPlusOne = J.AutoVar ->
        runCount += 1
        x.get() + 1
    test.equal runCount, 0
    watchOnce = Tracker.autorun (watchOnce) ->
        if watchOnce.firstRun
            xPlusOne.get()
    test.equal runCount, 1
    watchMany = Tracker.autorun (watchMany) ->
        xPlusOne.get()
    # runCount is still 1 because xPlusOne's computation
    # is still valid
    test.equal runCount, 1
    Tracker.flush()
    test.equal runCount, 1
    x.set 10
    test.equal runCount, 1
    Tracker.flush()
    test.equal runCount, 2
    Tracker.flush()
    test.equal runCount, 2
    x.set 20
    test.equal runCount, 2
    Tracker.flush()
    test.equal runCount, 3
    watchMany.stop()
    x.set 30
    Tracker.flush()
    watchOnce.stop()

Tinytest.add "AutoVar - Invalidation propagation 1", (test) ->
    x = new J.Var 5
    a = J.AutoVar -> x.get()
    b = J.AutoVar -> a.get()
    c = J.AutoVar -> b.get()
    d = J.AutoVar -> c.get()
    e = J.AutoVar -> d.get()
    test.equal e.get(), 5
    x.set 6
    test.equal e.get(), 6
    Tracker.flush()
    test.equal e.get(), 6

Tinytest.add "AutoVar - Invalidation propagation 2", (test) ->
    x = new J.Var 5
    a = J.AutoVar 'a', -> x.get()
    b = J.AutoVar 'b', -> a.get()
    c = J.AutoVar 'c', -> b.get()
    e = J.AutoVar 'e', -> c.get() + a.get()
    test.equal e.get(), 10
    x.set 6
    test.equal e.get(), 12
    Tracker.flush()
    test.equal e.get(), 12

Tinytest.add "AutoVar - Invalidation propagation order", (test) ->
    history = []
    x = new J.Var 5
    a = J.AutoVar 'a', ->
        history.push 'a'
        x.get()
    b = J.AutoVar 'b', ->
        history.push 'b'
        a.get()
    c = J.AutoVar 'c', ->
        history.push 'c'
        b.get()
    d = J.AutoVar 'd', ->
        history.push 'd'
        c.get()
    e = J.AutoVar 'e', ->
        history.push 'e'
        a.get() + c.get()

    test.equal history, []
    test.equal e.get(), 10
    test.equal history, ['e', 'a', 'c', 'b']
    history = []
    x.set 6
    test.equal history, []
    Tracker.flush()
    test.equal e.get(), 12
    test.isTrue 'a' in history
    test.isTrue 'b' in history
    test.isTrue 'c' in history
    test.isTrue 'e' in history


Tinytest.add "AutoVar - Can stop self from within computation", (test) ->
    a = J.AutoVar(
        -> a.stop() ? null
        true
    )
    Tracker.flush()
    test.isTrue a.stopped



Tinytest.add "Dependency - don't invalidate creator computation", (test) ->
    dep = null
    c1 = Tracker.autorun ->
        dep = new Tracker.Dependency()
        dep.depend()
        dep.changed()
    test.isFalse c1.invalidated
    dep.changed()
    test.isTrue c1.invalidated
    c1.stop()

Tinytest.add "AutoVar - sideways invalidation", (test) ->
    v = J.Var 5
    a = J.AutoVar(
        'a'
        ->
            console.log 'compute a'
            Tracker.onInvalidate -> console.log 'invalidated a'
            b = J.AutoList(
                'b'
                1
                (i) ->
                    console.log 'compute b[0]'
                    Tracker.onInvalidate -> console.log 'invalidated b[0]'
                    v.get()
            )
            b.get(0)
            b
    )
    c = J.AutoVar(
        'c'
        ->
            console.log 'compute c'
            Tracker.onInvalidate -> console.log 'invalidated c'
            myB = a.get()

            d = J.AutoVar(
                'd'
                ->
                    console.log 'compute d'
                    Tracker.onInvalidate -> console.log 'invalidated d'
                    if v.get() is 6
                        myB.get(0)
                    else null
            )
            d.get()
    )
    console.log 1
    c.get()
    console.log 2
    a.get()
    console.log 3
    Tracker.flush()
    console.log 4
    v.set 6
    console.log 5
    c.get()
    console.log 6
    a.stop()
    c.stop()












































































