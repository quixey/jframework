###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


Tinytest.add "_init", (test) ->
    # This test is just here to soak up
    # tinytest's init time so the other
    # tests' times aren't artificially high
    return


Tinytest.add "AutoDict - create with fieldSpec instead of keyFunc", (test) ->
    w = J.Var 9
    changeHist = []
    ad = J.AutoDict('ad',
        x: 5
        y: [6, 7]
        z: -> 'eight'
        w: -> w.get()
    ,
        onChange: (key, oldValue, newValue) ->
            changeHist.push [key, oldValue ? null, newValue ? null]
    )
    test.equal ad.toObj(),
        x: 5
        y: [6, 7]
        z: 'eight'
        w: 9
    test.equal ad.y().get(1), 7
    ad.y().push 88
    w.set 99
    Tracker.flush()
    test.equal ad.toObj(),
        x: 5
        y: [6, 7, 88]
        z: 'eight'
        w: 99
    Tracker.flush()
    test.equal J.List(changeHist).toArr(), [
        ['x', null, 5]
        ['y', null, [6, 7, 88]]
        ['z', null, 'eight']
        ['w', null, 9]
        ['w', 9, 99]
    ]
    ad.stop()


Tinytest.add "AutoDict - create with list of keys instead of keyFunc", (test) ->
    ad = J.AutoDict('ad',
        ['x', 'y', 'z']
        (key) -> "#{key}-v"
    )
    test.equal ad.getFields(),
        x: 'x-v'
        y: 'y-v'
        z: 'z-v'
    ad.stop()

    lst = J.List ['q', 'r']
    ad = J.AutoDict('ad',
        lst
        (key) -> "#{key}-v"
    )
    test.equal ad.getFields(),
        q: 'q-v'
        r: 'r-v'
    test.isUndefined ad.get('s')
    ad.stop()

    size = J.Var 5
    al = J.AutoList('haial',
        -> size.get()
        (i) -> "#{i}-k"
        true
    )
    ad = J.AutoDict('ad',
        al
        (key) -> "#{key}-v"
    )
    test.equal ad.hasKey('3-k'), true
    test.equal ad.get('3-k'), '3-k-v'
    test.equal ad.get('1-k'), '1-k-v'
    test.equal ad.getFields(),
        '0-k': '0-k-v'
        '1-k': '1-k-v'
        '2-k': '2-k-v'
        '3-k': '3-k-v'
        '4-k': '4-k-v'
    size.set 4
    Tracker.flush()

    if false
        # Old test when we wouldn't invalidate
        # the dict because its keys were an
        # actual J.List not an array
        test.equal ad.getFields(),
            '0-k': '0-k-v'
            '1-k': '1-k-v'
            '2-k': '2-k-v'
            '3-k': '3-k-v'
    al.stop()
    ad.stop()



Tinytest.addAsync "AfterFlush - sortKey basics", (test, onComplete) ->
    afCount = 0
    aafCount = 0
    Tracker.afterFlush(->
        aafCount += 1
        test.equal aafCount, 1, 'fail 1'
    , 0.7)
    Tracker.afterFlush(->
        aafCount += 1
        test.equal aafCount, 2, 'fail 2'
        Tracker.afterFlush(->
            aafCount += 1
            test.equal afCount, 2, 'fail 3'
            test.equal aafCount, 3, 'fail 4'
            Tracker.afterFlush(->
                aafCount += 1
            , 0.7)
            Tracker.afterFlush(->
                test.equal aafCount, 4, 'fail 5'
                aafCount += 1
                Tracker.afterFlush(->
                    test.equal aafCount, 6, 'fail 6'
                    _.defer -> onComplete()
                , 0.7)
            , 0.7)
            Tracker.afterFlush(->
                test.equal aafCount, 5, 'fail 7'
                aafCount += 1
            , 0.7)
            test.equal afCount, 2, 'fail 8'
            test.equal aafCount, 3, 'fail 9'
        , 0.7)
        Tracker.afterFlush ->
            afCount += 1
            test.equal afCount, 1, 'fail 10'
            test.equal aafCount, 2, 'fail 11'
        Tracker.afterFlush ->
            afCount += 1
            test.equal afCount, 2, 'fail 12'
            test.equal aafCount, 2, 'fail 13'
        test.equal afCount, 0, 'fail 14'
        test.equal aafCount, 2, 'fail 15'
    , 0.7)
    test.equal aafCount, 0, 'fail 16'


Tinytest.addAsync "AfterFlush - trigger high sortKey funcs after all onChange handlers", (test, onComplete) ->
    v = J.Var 6
    onChangeCount = 0
    Tracker.afterFlush(->
        test.equal onChangeCount, 1, 'fail 1'
    , 0.7)
    a = J.AutoVar('a',
        -> v.get()
        (oldA, newA) ->
            onChangeCount += 1
    )
    Tracker.afterFlush(->
        test.equal onChangeCount, 1, 'fail 2'
    , 0.7)
    test.equal onChangeCount, 0, 'fail 3'
    Tracker.flush()
    test.equal onChangeCount, 1, 'fail 4'
    Tracker.afterFlush(->
        test.equal onChangeCount, 3, 'fail 5'
    , 0.7)
    b = J.AutoVar('b',
        -> v.get() - v.get() % 2
        (oldB, newB) ->
            onChangeCount += 1
    )
    Tracker.afterFlush(->
        test.equal onChangeCount, 3, 'fail 6'
        a.stop()
        b.stop()
        onComplete()
    , 0.7)
    v.set 7
    test.equal onChangeCount, 1, 'fail 7'





Tinytest.add "AutoDict - deleting a key", (test) ->
    keys = J.List ['zero', 'one', 'two']
    x = J.Var 5
    hist = []

    ad = J.AutoDict(
        'ad'
        -> keys
        (key) ->
            hist.push key
            "v-#{key}, #{x.get()}"
    )

    test.equal ad.get('two'), 'v-two, 5'
    test.equal ad.get('one'), 'v-one, 5'
    x.set 6
    Tracker.flush()
    test.equal ad.get('one'), 'v-one, 6'
    hist = []
    keys.pop()
    test.isUndefined ad.get('two')
    test.equal hist, [] # Recomputing two would be particularly bad
    hist = []
    Tracker.flush()
    test.equal ad.getFields(), {'zero': 'v-zero, 6', one: 'v-one, 6'}
    test.equal hist, ['zero']
    Tracker.flush()



Tinytest.add "AutoDict - delete element onChange", (test) ->
    size = new J.Var 3
    changeHistory = []
    al = J.AutoDict(
        -> "#{x}" for x in [0...size.get()]
        (key) -> "val #{key}"
        onChange: (key, oldValue, newValue) ->
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

Tinytest.add "AutoDict - onChange", (test) ->
    changeHistory = []
    keysVar = J.Var ['a', 'b']
    ad = J.AutoDict(
        -> keysVar.get()
        (key) -> 5
        onChange: (key, oldValue, newValue) ->
            changeHistory.push [key, oldValue, newValue]
    )
    test.equal changeHistory, []
    Tracker.flush()
    test.equal changeHistory, [
        ['a', undefined, 5]
        ['b', undefined, 5]
    ]
    changeHistory = []
    keysVar.set ['c', 'a']
    test.equal changeHistory, []
    Tracker.flush()
    test.equal changeHistory, [
        ['b', 5, undefined]
        ['c', undefined, 5]
    ]
    test.equal ad.toObj(),
        a: 5
        c: 5
    ad.stop()


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

    lst = J.List([5, 3, [1], 4])
    test.notEqual lst.get(2), [1]

Tinytest.add "List - extend", (test) ->
    lst = J.List ['zero', 'one']
    valFuncHistory = []
    d = J.AutoDict(
        -> lst
        (x) ->
            valFuncHistory.push x
            "val for #{x}"
        onChange: true
    )
    Tracker.flush()
    test.equal valFuncHistory, ['zero', 'one']
    valFuncHistory = []
    lst.extend ['two', 'three']
    Tracker.flush()
    test.equal valFuncHistory, ['two', 'three']
    lst = J.List ['zero', 'one']
    d.stop()

    runCount = 0
    c = Tracker.autorun ->
        runCount += 1
        lst.toArr()
    lst.extend ['two', 'three']
    test.equal runCount, 1
    Tracker.flush()
    test.equal runCount, 2
    c.stop()
    Tracker.flush()


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
    Tracker.flush()
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

Tinytest.add "List - sort", (test) ->
    lst = J.List [4, 3, 2, 1, 0]
    sortedLst = null
    c = Tracker.autorun (c) ->
        sortedLst = lst.getSorted()
        if c.firstRun
            test.equal lst.toArr(), [4, 3, 2, 1, 0]
            test.equal sortedLst.toArr(), [0, 1, 2, 3, 4]
            lst.set 1, 5
        else
            test.equal lst.toArr(), [4, 5, 2, 1, 0]
            test.equal sortedLst.toArr(), [0, 1, 2, 4, 5]
            c.stop()
    Tracker.flush()


Tinytest.add "AutoDict - Basics", (test) ->
    size = new J.Var 3
    d = J.AutoDict(
        -> ['zero', 'one', 'two', 'three', 'four', 'five'][0...size.get()]
        (key) -> "#{key} is a number"
    )
    Tracker.flush()
    test.equal d.getKeys(), ['zero', 'one', 'two']
    test.equal d.toObj(), {'zero': "zero is a number", 'one': "one is a number", 'two': "two is a number"}
    test.equal d.size(), 3
    test.equal d.get('two'), "two is a number"
    test.isUndefined d.get('four')
    size.set 4
    test.equal d.size(), 4
    Tracker.flush()
    test.equal d.size(), 4
    Tracker.flush()
    test.equal d.size(), 4
    test.equal d.getKeys(), ['zero', 'one', 'two', 'three']
    test.equal d.get('three'), "three is a number"


Tinytest.add "AutoDict - computation ownership", (test) ->
    valueFuncRuns = 0
    d = J.AutoDict(
        -> ['j', 'k']
        (key) ->
            valueFuncRuns += 1
            key + '-v'
    )

    c = Tracker.autorun (c) ->
        d.getFields()

    test.equal valueFuncRuns, 2
    test.isTrue d._fields['j'].creator is null
    Tracker.flush()
    c.stop()
    Tracker.flush()
    test.equal valueFuncRuns, 2


Tinytest.add "AutoDict - reactivity", (test) ->
    coef = new J.Var 2
    size = new J.Var 3
    d = J.AutoDict(
        ->
            ['3', '5', '9', '7'][0...size.get()]
        (key) ->
            if key is '7' then 'xxx' else coef.get() * parseInt(key)
    )
    dHistory = []
    watcher = Tracker.autorun =>
        dHistory.push d.getFields()
    watcher.onInvalidate => console.info "INVALIDATED WATCHER"
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
    d.stop()


Tinytest.add "AutoDict - laziness", (test) ->
    coef = new J.Var 2
    size = new J.Var 3
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
    coef = new J.Var 10
    size = new J.Var 3
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
    test.throws -> al.set 2, 2
    size.set 2
    coef.set 100
    test.equal sizeFuncRunCount, 1
    test.equal valueFuncRunCount, 3
    Tracker.flush()
    test.equal sizeFuncRunCount, 2
    test.equal valueFuncRunCount, 5
    test.equal al.toArr(), [0, 100]
    coef.set 1000
    Tracker.flush()
    test.equal al.toArr(), [0, 1000]
    test.equal sizeFuncRunCount, 2
    test.equal valueFuncRunCount, 7


Tinytest.add "AutoList - onChange", (test) ->
    coef = new J.Var 10
    size = new J.Var 3
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
    Tracker.flush()
    test.equal al.size(), 5
    test.equal onChangeHistory, [
        [3, undefined, 30, 5]
        [4, undefined, 40, 5]
    ]
    onChangeHistory = []
    size.set 4
    Tracker.flush()
    test.equal al.size(), 4
    test.equal onChangeHistory, [
        [4, 40, undefined, 4]
    ]
    coef.set 100
    Tracker.flush()
    test.equal al.get(2), 200
    test.isTrue _.any (J.util.equals(x, [1, 10, 100, 4]) for x in onChangeHistory)
    test.isTrue _.any (J.util.equals(x, [2, 20, 200, 4]) for x in onChangeHistory)
    test.isTrue _.any (J.util.equals(x, [3, 30, 300, 4]) for x in onChangeHistory)


Tinytest.add "AutoList - onChange 2", (test) ->
    coef = new J.Var 10
    size = new J.Var 5
    sizeFuncRunCount = 0
    valueFuncRunCount = 0
    onChangeHistory = []
    al = J.AutoList(
        ->
            sizeFuncRunCount += 1
            size.get()
        (i) ->
            console.log 'compute', i
            valueFuncRunCount += 1
            i * coef.get()
        (i, oldValue, newValue) ->
            console.log 'onchange', i, oldValue, newValue
            onChangeHistory.push [i, oldValue, newValue, @size()]
    )
    Tracker.flush()
    onChangeHistory = []
    size.set 4
    Tracker.flush()
    test.equal onChangeHistory, [
        [4, 40, undefined, 4]
    ]
    al.stop()


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
    Tracker.flush()
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
    Tracker.flush()
    test.equal concatted.get(2), 6
    test.equal concatted.toArr(), [3, 5, 6, 7, 8]
    test.throws -> concatted.get 6
    lst1.push 'x'
    Tracker.flush()
    test.equal concatted.toArr(), [3, 5, 6, 7, 8]
    c = Tracker.autorun (c) ->
        concatted = lst1.getConcat lst2
    test.equal concatted.toArr(), [3, 5, 6, 'x', 7, 8]
    lst1.push 'y'
    Tracker.flush()
    test.equal concatted.toArr(), [3, 5, 6, 'x', 'y', 7, 8]
    lst2.set 1, 'z'
    Tracker.flush()
    test.equal concatted.toArr(), [3, 5, 6, 'x', 'y', 7, 'z']
    test.equal concatted.get(0), 3
    c.stop()
    Tracker.flush() # Intentionally testing flushing after stopping

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


Tinytest.add "AutoDict - Don't recalculate dead keys", (test) ->
    size = new J.Var 3
    val = new J.Var 100
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
    Tracker.flush()
    test.equal d.toObj(),
        0: 100
        1: 101
        2: 102
    test.equal keyFuncRunCount, 1
    test.equal valueFuncRunCount, 3
    size.set 2
    Tracker.flush()
    test.equal valueFuncRunCount, 3
    test.isUndefined d.get('2')
    test.equal valueFuncRunCount, 3
    test.equal d.get('1'), 101
    test.equal valueFuncRunCount, 3
    val.set 200
    Tracker.flush()
    test.isUndefined d.get('2')
    test.equal valueFuncRunCount, 5
    test.equal d.get('1'), 201
    test.equal valueFuncRunCount, 5
    Tracker.flush()
    test.equal valueFuncRunCount, 5
    d.stop()


Tinytest.add "AutoDict - Make sure key still exists when expediting value recalculation", (test) ->
    size = new J.Var 3
    val = new J.Var 100
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




Tinytest.add "Dict - don't invalidate creator computation", (test) ->
    runCount = 0
    runCount2 = 0

    d = null
    console.log 1
    c1 = Tracker.autorun (c) ->
        console.log 'run1'
        # Since this autorun is creating d,
        # it won't invalidate when it's the
        # one mutating d.
        runCount += 1
        d ?= J.Dict()
        console.log 11
        d.size()
        console.log 12
        d.setOrAdd 'a', (d.get('a') ? 0) + 1
        console.log 13
        d.hasKey 'b'
        console.log 14
        d.setOrAdd 'b', 4
        console.log 15
        test.isTrue d.hasKey 'b'
        console.log 16
        ret = d.a()
        console.log 'done1'
        ret
    c2 = Tracker.autorun ->
        console.log 'run2'
        runCount2 += 1
        ret = d.get('a')
        console.log 'done2'
        ret
    console.log 2
    test.equal runCount, 1
    test.equal runCount2, 1
    Tracker.flush()
    console.log 3
    test.equal runCount, 1
    test.equal runCount2, 1



Tinytest.addAsync "AutoList - Maps don't stop prematurely", (test, onComplete) ->
    coef = new J.Var 2
    lst = J.List [3, 4, 5]
    mappedLst = lst.map (v) -> coef.get() * v
    test.equal mappedLst.getValues(), [6, 8, 10]
    coef.set 3
    test.equal mappedLst.getValues(), [6, 8, 10]

    av = J.AutoVar 'av',
        -> lst.map (v) -> coef.get() * v

    test.equal av.get().getValues(), [9, 12, 15]
    coef.set 4
    Tracker.flush()
    test.equal av.get().getValues(), [12, 16, 20]
    av.stop()
    test.throws -> av.get().getValues()

    onComplete()




Tinytest.add "AutoVar - Invalidation non-propagation", (test) ->
    history = []
    x = new J.Var 5
    a = J.AutoVar 'a', ->
        history.push 'a'
        x.get()
    b = J.AutoVar 'b', ->
        history.push 'b'
        Math.floor(a.get() / 100) * 100 # Round down to nearest 100
    c = J.AutoVar 'c', ->
        history.push 'c'
        b.get()
    d = J.AutoVar 'd', ->
        history.push 'd'
        c.get()
    test.equal c.get(), 0
    test.equal history, ['c', 'b', 'a']
    history = []
    x.set 55
    Tracker.flush()
    test.equal c.get(), 0
    test.isTrue 'a' in history
    test.isTrue 'b' in history
    test.isFalse 'c' in history # Currently fails
    history = []
    x.set 101
    Tracker.flush()
    test.equal c.get(), 100
    test.isTrue 'a' in history
    test.isTrue 'c' in history
    history = []
    d.get()
    history = []
    x.set 102
    Tracker.flush()
    d.get()
    test.isTrue 'a' in history
    test.isTrue 'b' in history
    test.isFalse 'c' in history
    test.isFalse 'd' in history


Tinytest.add "Programming patterns - Mutation in a forEach", (test) ->
    mySet = {}

    J.List(['a', 'b', 'c']).forEach (x) ->
        mySet[x] = true

    test.equal mySet, a: true, b: true, c: true


Tinytest.add "List - slice", (test) ->
    lst = J.List ['zero', 'one', 'two', 'three', 'four']
    runCount = 0
    s = J.AutoVar(
        's'
        ->
            runCount += 1
            lst.slice 1, 2
    )
    test.equal s.get().size(), 1
    test.equal s.get().get(0), 'one'
    s.get()
    s.get()
    lst.set 1, 'ONE'
    Tracker.flush()
    test.equal s.get().get(0), 'ONE'
    s.get()
    s.get()
    # test.equal runCount, 1
    lst.set 2, 'TWO'
    Tracker.flush()
    lst.set 4, 'FOUR'
    Tracker.flush()
    test.equal s.get().get(0), 'ONE'
    # test.equal runCount, 1























