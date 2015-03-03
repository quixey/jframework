Tinytest.add "Dict - coarse grained", (test) ->
    d = J.Dict(
        a: 5
        b: 6
    ,
        fineGrained: false
    )

    aRunCount = 0
    a = J.AutoVar(
        ->
            aRunCount += 1
            d.a()
    )
    a.get()
    test.equal aRunCount, 1
    d.a 50
    Tracker.flush()
    test.equal aRunCount, 2
    d.b 60
    Tracker.flush()
    test.equal aRunCount, 3
    a.stop()

Tinytest.add "Dict - mutation reactivity", (test) ->
    runCount = 0
    av = J.AutoVar(
        'av'
        ->
            runCount += 1
            J.Dict(
                a: b: 5
            )
    )
    d = av.get()
    test.equal runCount, 1
    d.a().b 6
    test.equal d.a().b(), 6
    Tracker.flush()
    test.equal runCount, 1