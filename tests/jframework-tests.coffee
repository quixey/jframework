Tinytest.add "_init", (test) ->
    # This test is just here to soak up
    # tinytest's init time so the other
    # tests' times aren't artificially high
    return

Tinytest.add "AutoDict - delete element onChange", (test) ->
    size = new ReactiveVar 3
    changeHistory = []
    al = J.AutoDict(
        -> "#{x}" for x in [0...size.get()]
        (key) -> "val #{key}"
        (key, oldValue, newValue) ->
            changeHistory.push [key, oldValue, newValue]
    )
    test.equal al.toObj(),
        0: 'val 0'
        1: 'val 1'
        2: 'val 2'
    test.equal changeHistory, []
    Tracker.flush()
    test.equal changeHistory, [
        ['0', undefined, 'val 0']
        ['1', undefined, 'val 1']
        ['2', undefined, 'val 2']
    ]
    changeHistory = []
    size.set 2
    test.equal changeHistory, []
    Tracker.flush()
    test.equal changeHistory, [
        ['2', 'val 2', undefined]
    ]


Tinytest.add "Dict - basics", (test) ->
    d = J.Dict()
    d.setOrAdd x: 5
    test.equal d.get('x'), 5
    test.equal d.size(), 1
    test.throws -> d.set 'newkey': 8
    d.setOrAdd y: 7
    test.equal d.toObj(),
        x: 5
        y: 7
    d.clear()
    test.equal d.toObj(), {}
    test.equal d.size(), 0


Tinytest.add "List - basics", (test) ->
    lst = J.List [6, 4]
    test.isTrue lst.contains 4
    test.isFalse lst.contains "4"
    test.equal lst.get(0), 6
    test.throws -> lst.get '0'
    test.throws -> lst.get 2
    test.throws -> lst.get 1.5
    test.equal lst.join('*'), "6*4"
    test.equal lst.map((x) -> 2 * x).toArr(), [12, 8]
    test.equal lst.toArr(), [6, 4]
    lst.push 5
    test.equal lst.toArr(), [6, 4, 5]
    test.equal lst.getSorted().toArr(), [4, 5, 6]
    test.equal lst.toArr(), [6, 4, 5]
    lst.sort()
    test.equal lst.toArr(), [4, 5, 6]
    test.isTrue lst.deepEquals J.List [4, 5, 6]

    lst = J.List([5, 3, [1], 4])
    test.notEqual lst.get(2), [1]
    test.isTrue lst.get(2).deepEquals J.List [1]



Tinytest.add "Dict and List reactivity 1", (test) ->
    lst = J.List [0, 1, 2, 3, 4]
    testOutputs = []
    c = Tracker.autorun (c) ->
        testOutputs.push lst.get(3)
    test.equal testOutputs, [3]
    lst.set 3, 103
    lst.set 3, 203
    test.equal testOutputs, [3]
    Tracker.flush()
    test.equal testOutputs, [3, 203]
    c.stop()

Tinytest.add "Dict and List reactivity 2", (test) ->
    lst = J.List [0, 1, 2, 3, 4]
    nonreactiveMappedLst = lst.map (x) -> 2 * x
    test.equal nonreactiveMappedLst.toArr(), [0, 2, 4, 6, 8], "fail 1"

    reactiveMappedLst = null
    c = Tracker.autorun (c) ->
        reactiveMappedLst = lst.map (x) -> 2 * x
    test.equal reactiveMappedLst.toArr(), [0, 2, 4, 6, 8], "fail 2"
    Tracker.flush()
    test.equal reactiveMappedLst.toArr(), [0, 2, 4, 6, 8], "fail 2.1"

    lst.set 2, 102
    test.equal nonreactiveMappedLst.toArr(), [0, 2, 4, 6, 8], "fail 3"
    test.equal reactiveMappedLst.toArr(), [0, 2, 204, 6, 8], "fail 4"

    c.stop()

Tinytest.add "Dict and List reactivity 3", (test) ->
    lst = J.List [0, 1, 2, 3, 4]
    c = Tracker.autorun ->
        lst.reverse()
    test.equal lst.toArr(), [4, 3, 2, 1, 0], "Didn't reverse"
    Tracker.flush()
    test.equal lst.toArr(), [4, 3, 2, 1, 0], "Screwed up the reverse"
    c.stop()

Tinytest.add "Dict and List reactivity 4", (test) ->
    lst = J.List [4, 3, 2, 1, 0]
    sortedLst = []
    c = Tracker.autorun ->
        sortedLst = lst.getSorted()
    test.equal lst.toArr(), [4, 3, 2, 1, 0]
    test.equal sortedLst.toArr(), [0, 1, 2, 3, 4]
    lst.set 1, 5
    test.equal lst.toArr(), [4, 5, 2, 1, 0]
    test.equal sortedLst.toArr(), [0, 1, 2, 3, 4]
    Tracker.flush()
    test.equal sortedLst.toArr(), [0, 1, 2, 4, 5]

    c.stop()


Tinytest.add "List - resize", (test) ->
    lst = J.List [0, 1, 2, 3, 4]
    size = lst.size()
    test.equal size, 5
    c = Tracker.autorun ->
        size = lst.size()
    lst.resize 10
    test.equal size, 5
    Tracker.flush()
    test.equal size, 10
    test.equal lst.get(9), undefined
    test.throws -> lst.get(10)
    c.stop()

Tinytest.add "AutoVar - basics 1", (test) ->
    x = new ReactiveVar 5
    xPlusOne = J.AutoVar -> x.get() + 1
    test.equal xPlusOne.get(), 6
    x.set 10
    test.equal xPlusOne.get(), 11
    Tracker.flush()
    test.equal xPlusOne.get(), 11

Tinytest.add "AutoVar - be lazy when no one is looking", (test) ->
    x = new ReactiveVar 5
    runCount = 0
    xPlusOne = J.AutoVar ->
        runCount += 1
        x.get() + 1
    xPlusOne.tag = 'xPlusOne'
    test.equal runCount, 0
    x.set 10
    test.equal runCount, 0
    Tracker.flush()
    test.equal runCount, 0
    test.equal xPlusOne.get(), 11
    test.equal runCount, 1, "fail 1"
    test.equal xPlusOne.get(), 11
    test.equal runCount, 1, "fail 2"
    test.isFalse xPlusOne._var.dep.hasDependents(), "Why do you have dependents? (1)"
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
    test.isFalse xPlusOne._var.dep.hasDependents(), "Why do you have dependents? (2)"


Tinytest.add "AutoVar - don't be lazy if someone is looking", (test) ->
    x = new ReactiveVar 5
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
    test.isTrue xPlusOne._var.dep.hasDependents(), "Why don't you have dependents?"
    test.equal runCount, 2
    Tracker.flush()
    test.equal runCount, 3
    watchMany.stop()
    x.set 30
    test.isFalse xPlusOne._var.dep.hasDependents(), "Why do you have dependents? (1)"
    Tracker.flush()
    test.isFalse xPlusOne._var.dep.hasDependents(), "Why do you have dependents? (2)"
    watchOnce.stop()


Tinytest.add "AutoDict - Basics", (test) ->
    size = new ReactiveVar 3
    d = J.AutoDict(
        -> ['zero', 'one', 'two', 'three', 'four', 'five'][0...size.get()]
        (key) -> "#{key} is a number"
    )
    test.equal d.getKeys(), ['zero', 'one', 'two']
    test.equal d.toObj(), {'zero': "zero is a number", 'one': "one is a number", 'two': "two is a number"}
    test.equal d.size(), 3
    test.equal d.get('two'), "two is a number"
    test.isUndefined d.get('four')
    size.set 4
    test.equal d.size(), 4
    Tracker.flush()
    test.equal d.size(), 4
    test.equal d.getKeys(), ['zero', 'one', 'two', 'three']
    test.equal d.get('three'), "three is a number"


Tinytest.add "AutoDict - reactivity", (test) ->
    coef = new ReactiveVar 2
    size = new ReactiveVar 3
    d = J.AutoDict(
        -> ['3', '5', '9', '7'][0...size.get()]
        (key) -> if key is '7' then 'xxx' else coef.get() * parseInt(key)
    )
    dHistory = []
    watcher = Tracker.autorun =>
        dHistory.push d.getFields()
    test.equal dHistory.pop(), {
        3: 6
        5: 10
        9: 18
    }
    coef.set 10
    Tracker.flush()
    test.equal dHistory.pop(), {
        3: 30
        5: 50
        9: 90
    }
    size.set 4
    Tracker.flush()
    test.equal dHistory.pop(), {
        3: 30
        5: 50
        9: 90
        7: 'xxx'
    }
    watcher.stop()

    watcher = Tracker.autorun =>
        dHistory.push d.get('7')
    test.equal dHistory.pop(), 'xxx'
    coef.set 4
    Tracker.flush()
    test.equal dHistory.length, 0
    watcher.stop()


Tinytest.add "AutoDict - laziness", (test) ->
    coef = new ReactiveVar 2
    size = new ReactiveVar 3
    keyFuncRunCount = 0
    valueFuncRunCount = 0
    d = J.AutoDict(
        ->
            keyFuncRunCount += 1
            ['3', '5', '9', '7'][0...size.get()]
        (key) ->
            valueFuncRunCount += 1
            if key is '7' then 'xxx' else coef.get() * parseInt(key)
    )
    test.equal keyFuncRunCount, 0
    test.equal valueFuncRunCount, 0
    test.equal d.get('3'), 6
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 1
    test.equal d.get('3'), 6
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 1
    Tracker.flush()
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 1
    test.equal d.get('9'), 18
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 2
    Tracker.flush()
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 2


Tinytest.add "AutoList - reactivity 1", (test) ->
    coef = new ReactiveVar 10
    size = new ReactiveVar 3
    sizeFuncRunCount = 0
    valueFuncRunCount = 0
    al = J.AutoList(
        ->
            sizeFuncRunCount += 1
            size.get()
        (i) ->
            valueFuncRunCount += 1
            i * coef.get()
    )
    test.equal sizeFuncRunCount, 0
    test.equal valueFuncRunCount, 0
    test.equal al.toArr(), [0, 10, 20]
    test.throws -> al.resize 5
    test.throws -> al.set 2, 2
    size.set 2
    coef.set 100
    test.equal sizeFuncRunCount, 1
    test.equal valueFuncRunCount, 3
    Tracker.flush()
    test.equal al.toArr(), [0, 100]
    test.equal sizeFuncRunCount, 2
    test.equal valueFuncRunCount, 5


Tinytest.add "AutoList - onChange", (test) ->
    coef = new ReactiveVar 10
    size = new ReactiveVar 3
    sizeFuncRunCount = 0
    valueFuncRunCount = 0
    onChangeHistory = []
    al = J.AutoList(
        ->
            sizeFuncRunCount += 1
            size.get()
        (i) ->
            valueFuncRunCount += 1
            i * coef.get()
        (i, oldValue, newValue) ->
            onChangeHistory.push [i, oldValue, newValue, @size()]
    )
    test.equal sizeFuncRunCount, 0
    test.equal valueFuncRunCount, 0
    test.equal onChangeHistory, []
    Tracker.flush()
    test.equal valueFuncRunCount, 3
    test.equal onChangeHistory, [
        [0, undefined, 0, 3]
        [1, undefined, 10, 3]
        [2, undefined, 20, 3]
    ]
    onChangeHistory = []
    test.equal al.toArr(), [0, 10, 20]
    test.equal valueFuncRunCount, 3
    size.set 5
    test.equal onChangeHistory, []
    test.equal al.size(), 5
    test.equal onChangeHistory, []
    Tracker.flush()
    test.equal onChangeHistory, [
        [3, undefined, 30, 5]
        [4, undefined, 40, 5]
    ]
    test.equal al.size(), 5
    onChangeHistory = []
    size.set 4
    test.equal al.size(), 4
    test.equal onChangeHistory, []
    Tracker.flush()
    test.equal onChangeHistory, [
        [4, 40, undefined, 4]
    ]
    coef.set 100
    test.equal al.get(2), 200
    test.equal onChangeHistory, [
        [4, 40, undefined, 4]
    ]
    Tracker.flush()
    test.isTrue _.any (J.util.equals(x, [1, 10, 100, 4]) for x in onChangeHistory)
    test.isTrue _.any (J.util.equals(x, [2, 20, 200, 4]) for x in onChangeHistory)
    test.isTrue _.any (J.util.equals(x, [3, 30, 300, 4]) for x in onChangeHistory)


Tinytest.add "List - onChange 2", (test) ->
    coef = new ReactiveVar 10
    size = new ReactiveVar 5
    sizeFuncRunCount = 0
    valueFuncRunCount = 0
    onChangeHistory = []
    al = J.AutoList(
        ->
            sizeFuncRunCount += 1
            size.get()
        (i) ->
            valueFuncRunCount += 1
            i * coef.get()
        (i, oldValue, newValue) ->
            onChangeHistory.push [i, oldValue, newValue, @size()]
    )
    Tracker.flush()
    onChangeHistory = []
    size.set 4
    Tracker.flush()
    test.equal onChangeHistory, [
        [4, 40, undefined, 4]
    ]


Tinytest.add "List - reverse", (test) ->
    lst = J.List [0, 1, 2, 3]
    reversed = lst.getReversed()
    test.equal lst.toArr(), [0, 1, 2, 3]
    test.equal reversed.toArr(), [3, 2, 1, 0]
    lst.set 2, 22
    test.equal reversed.toArr(), [3, 2, 1, 0]
    test.equal lst.toArr(), [0, 1, 22, 3]
    reversed = null
    c = Tracker.autorun (c) ->
        reversed = lst.getReversed()
    test.equal reversed.toArr(), [3, 22, 1, 0]
    lst.set 2, 222
    test.equal reversed.toArr(), [3, 222, 1, 0]
    test.isFalse c.invalidated
    lst.set 2, 2
    c.stop()
    test.throws -> reversed.get 2
    test.throws -> reversed.toArr()
    test.equal lst.toArr(), [0, 1, 2, 3]


Tinytest.add "List - getConcat", (test) ->
    lst1 = J.List [3, 5, 6]
    lst2 = J.List [7, 8]
    concatted = lst1.getConcat lst2
    test.equal concatted.get(2), 6
    test.equal concatted.toArr(), [3, 5, 6, 7, 8]
    test.throws -> concatted.get 6
    lst1.push 'x'
    test.equal concatted.toArr(), [3, 5, 6, 7, 8]
    c = Tracker.autorun (c) ->
        concatted = lst1.getConcat lst2
    test.equal concatted.toArr(), [3, 5, 6, 'x', 7, 8]
    lst1.push 'y'
    test.equal concatted.toArr(), [3, 5, 6, 'x', 'y', 7, 8]
    lst2.set 1, 'z'
    test.equal concatted.toArr(), [3, 5, 6, 'x', 'y', 7, 'z']
    test.equal concatted.get(0), 3
    c.stop()
    test.throws -> concatted.get 0

Tinytest.add "Dict - encode/decode key", (test) ->
    J.Dict.encodeKey 'test' is '<<KEY>>test'
    a = [1, 2, ['3', true, 4], '5']
    test.equal a, J.Dict.decodeKey J.Dict.encodeKey(_.clone(a))

Tinytest.add "List - .contains reactivity", (test) ->
    lst = J.List [0, 1, 2, 3, 4]
    containsHistory = []
    lastContains = null
    Tracker.autorun ->
        lastContains = lst.contains 2
        containsHistory.push lastContains
    test.isTrue lastContains
    lst.set 3, 33
    Tracker.flush()
    test.isTrue lastContains
    lst.set 2, 22
    Tracker.flush()
    test.isFalse lastContains
    lst.set 4, 2
    Tracker.flush()
    test.isTrue lastContains
    lst.set 4, 4
    Tracker.flush()
    test.isFalse lastContains
    lst.push 5
    Tracker.flush()
    test.isFalse lastContains
    lst.push 2
    Tracker.flush()
    test.isTrue lastContains
    lst.push 3
    Tracker.flush()
    test.isTrue lastContains
    lst.resize 20
    Tracker.flush()
    test.isTrue lastContains
    lst.resize 4
    test.isTrue lastContains
    Tracker.flush()
    test.isFalse lastContains

Tinytest.add "AutoVar - indexOf", (test) ->
    size = new ReactiveVar 3
    valueFuncRunCount = 0
    a = J.AutoVar(
        ->
            valueFuncRunCount += 1
            [0...size.get()]
    )
    test.equal valueFuncRunCount, 0
    test.isTrue a.contains 2
    test.equal valueFuncRunCount, 1
    test.isTrue a.contains 1
    test.equal valueFuncRunCount, 1
    size.set 2
    test.isTrue a.contains 1
    test.equal valueFuncRunCount, 2
    test.isFalse a.contains 2
    test.equal valueFuncRunCount, 2
    a.stop()

Tinytest.add "AutoVar - indexOf reactivity", (test) ->
    size = new ReactiveVar 3
    aRunCount = 0
    aContains2RunCount = 0
    a = J.AutoVar(
        ->
            aRunCount += 1
            [0...size.get()]
    )
    aContains2 = J.AutoVar(
        ->
            aContains2RunCount += 1
            a.contains 2
    )
    Tracker.flush()
    test.equal aRunCount, 0
    test.equal aContains2RunCount, 0
    test.isTrue aContains2.get()
    test.equal aRunCount, 1
    test.equal aContains2RunCount, 1
    test.isTrue a.contains(1)
    test.equal aRunCount, 1
    test.equal aContains2RunCount, 1
    size.set 4
    test.isTrue aContains2.get()
    test.equal aRunCount, 2
    test.equal aContains2RunCount, 1
    size.set 2
    test.isFalse aContains2.get()
    test.equal aRunCount, 3
    test.equal aContains2RunCount, 2
    a.stop()
    aContains2.stop()


Tinytest.add "AutoDict - Don't recalculate dead keys", (test) ->
    size = new ReactiveVar 3
    val = new ReactiveVar 100
    keyFuncRunCount = 0
    valueFuncRunCount = 0
    d = J.AutoDict(
        ->
            keyFuncRunCount += 1
            "#{x}" for x in [0...size.get()]
        (key) ->
            valueFuncRunCount += 1
            val.get() + parseInt key
    )
    test.equal keyFuncRunCount, 0
    test.equal valueFuncRunCount, 0
    test.equal d.toObj(),
        0: 100
        1: 101
        2: 102
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 3
    size.set 2
    test.equal valueFuncRunCount, 3
    test.isUndefined d.get('2')
    test.equal valueFuncRunCount, 3
    test.equal d.get('1'), 101
    test.equal valueFuncRunCount, 3
    val.set 200
    test.equal valueFuncRunCount, 3
    test.isUndefined d.get('2')
    test.equal valueFuncRunCount, 5 # Because we flush everything
    test.equal d.get('1'), 201
    test.equal valueFuncRunCount, 5
    Tracker.flush()
    test.equal valueFuncRunCount, 5
    d.stop()


Tinytest.add "AutoDict - Make sure key still exists when expediting value recalculation", (test) ->
    size = new ReactiveVar 3
    val = new ReactiveVar 100
    keysFuncRunCount = 0
    valueFuncRunCount = 0
    d = J.AutoDict(
        ->
            keysFuncRunCount += 1
            "#{x}" for x in [0...size.get()]
        (key) ->
            valueFuncRunCount += 1
            val.get() + parseInt key
    )
    size.set 2
    test.isUndefined d.get('2')
    Tracker.flush()
    test.equal d.toObj(),
        0: 100
        1: 101
    val.set 200
    size.set 1
    test.isUndefined d.get('1')
    size.set 0
    val.set 300
    test.isUndefined d.get('0')


Tinytest.add "AutoVar - Invalidation propagation 1", (test) ->
    x = new ReactiveVar 5
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
    x = new ReactiveVar 5
    a = J.AutoVar -> x.get()
    b = J.AutoVar -> a.get()
    c = J.AutoVar -> b.get()
    d = J.AutoVar -> c.get()
    e = J.AutoVar -> c.get() + a.get()
    test.equal e.get(), 10
    x.set 6
    test.equal e.get(), 12
    Tracker.flush()
    test.equal e.get(), 12

Tinytest.add "AutoVar - Invalidation propagation order", (test) ->
    history = []
    x = new ReactiveVar 5
    a = J.AutoVar ->
        history.push 'a'
        x.get()
    a.tag = 'a'
    b = J.AutoVar ->
        history.push 'b'
        a.get()
    b.tag = 'b'
    c = J.AutoVar ->
        history.push 'c'
        b.get()
    c.tag = 'c'
    d = J.AutoVar ->
        history.push 'd'
        c.get()
    d.tag = 'd'
    e = J.AutoVar ->
        history.push 'e'
        a.get() + c.get()
    e.tag = 'e'

    test.equal history, []
    test.equal e.get(), 10
    test.equal history, ['e', 'a', 'c', 'b']
    history = []
    x.set 6
    test.equal history, []
    test.equal e.get(), 12
    test.equal history, ['a', 'e', 'b', 'c']



Tinytest.add "AutoVar - Invalidation non-propagation", (test) ->
    history = []
    x = new ReactiveVar 5
    a = J.AutoVar ->
        history.push 'a'
        x.get()
    b = J.AutoVar ->
        history.push 'b'
        Math.floor(a.get() / 100) * 100 # Round down to nearest 100
    c = J.AutoVar ->
        history.push 'c'
        b.get()
    test.equal c.get(), 0
    test.equal history, ['c', 'b', 'a']
    history = []
    x.set 55
    test.equal c.get(), 0
    test.isTrue 'a' in history
    test.isTrue 'b' in history
    test.isFalse 'c' in history # Currently fails
    history = []
    x.set 101
    test.equal c.get(), 100
    test.isTrue 'a' in history
    test.isTrue 'c' in history
















































