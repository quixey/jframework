# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


Tinytest.addAsync "List - map", (test, onComplete) ->
    lst = J.List ['zero', 'one', 'two', 'three']
    mappedLst = []
    a = J.AutoVar(
        'a'
        ->
            mappedLst = lst.map (x) -> "mapped-#{x}"
            5
    )
    a.get()
    test.equal mappedLst.getValues(),
        ['mapped-zero', 'mapped-one', 'mapped-two', 'mapped-three']

    a.stop()
    onComplete()


Tinytest.add "List - sideways invalidation", (test) ->
    v = J.Var 10

    a = J.AutoVar(
        'a'
        ->
            Tracker.onInvalidate -> console.log 'invalidated a!'
            console.log 'recalc a'

            e = J.AutoVar(
                'e'
                ->
                    Tracker.onInvalidate -> console.log 'invalidated e!'
                    console.log 'recalc e'
                    ed = J.AutoDict
                        x: ->
                            console.log 'recalc x'
                            v.get()
                            [['sup'], [111]]
                    eret = ed.x()
                    console.log 'e done'
                    eret
            )

            ret = xxx: yyy: e.get()

            v.get()

            console.log 'done a'
            ret
    )

    b = J.AutoVar(
        'b'
        ->
            Tracker.onInvalidate -> console.log 'invalidated b!'
            console.log 'recalc b'
            dx = a.get().xxx().yyy()

            c = J.AutoVar(
                'c'
                ->
                    Tracker.onInvalidate -> console.log 'invalidated c!'
                    console.log 'recalc c'
                    v.get()
                    cRet = dx.get(1)
                    console.log 'done c'
                    cRet
            )
            bRet = c.get()

            console.log 'done b'
            bRet
    )

    test.equal b.get().get(0), 111
    v.set 11
    test.equal b.get().get(0), 111


Tinytest.add "List - splice", (test) ->
    lHist = []
    lst = J.List [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        onChange: (i, oldV, newV) ->
            lHist.push [i, oldV, newV]

    hist = []
    a = J.AutoVar(
        'a',
        ->
            lst.tryGet(6) ? 123
        (oldA, newA) ->
            hist.push newA
    )
    Tracker.flush()
    test.equal hist.pop(), 6
    test.equal lHist.length, 0
    test.equal lst.splice(1, 2).toArr(), [1, 2]
    Tracker.flush()
    test.equal lHist, [
        [1, 1, 3]
        [2, 2, 4]
        [3, 3, 5]
        [4, 4, 6]
        [5, 5, 7]
        [6, 6, 8]
        [7, 7, 9]
        [9, 9, undefined]
        [8, 8, undefined]
    ]
    lHist = []
    test.equal hist.pop(), 8
    test.equal lst.splice(1, 2).toArr(), [3, 4]
    Tracker.flush()
    test.equal lHist, [
        [1, 3, 5]
        [2, 4, 6]
        [3, 5, 7]
        [4, 6, 8]
        [5, 7, 9]
        [7, 9, undefined]
        [6, 8, undefined]
    ]
    test.equal hist.length, 1
    test.equal hist.pop(), 123
