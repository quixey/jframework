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