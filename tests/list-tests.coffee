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