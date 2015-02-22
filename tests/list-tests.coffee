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