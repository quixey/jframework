Tinytest.add "AutoVar - currentValueMightChange", (test) ->
    v = J.Var 5
    a = J.AutoVar(
        'a'
        -> v.get()
    )
    b = J.AutoVar(
        'b'
        -> a.get()
    )
    c = J.AutoVar(
        'c'
        -> Math.max a.get(), 10
        true
    )
    dHistory = []
    d = J.AutoVar(
        'd'
        -> c.get()
        (oldD, newD) ->
            dHistory.push [oldD, newD]
    )
    test.isTrue a.currentValueMightChange()
    a.get()
    test.isFalse a.currentValueMightChange()
    test.isTrue c.currentValueMightChange()
    Tracker.flush()
    v.set 6
    test.isTrue a.currentValueMightChange()
    test.isTrue b.currentValueMightChange()
    test.isTrue c.currentValueMightChange()
    test.isTrue d.currentValueMightChange()
    Tracker.flush()
    test.isFalse c.currentValueMightChange()
    test.isFalse d.currentValueMightChange()
    test.equal dHistory, [[undefined, 10]]
    a.stop()
    b.stop()
    c.stop()
    d.stop()