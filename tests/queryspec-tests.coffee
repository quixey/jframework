Tinytest.add 'QuerySpec merging', (test) ->
    testEqual = (a, b) ->
        test.equal EJSON.stringify(a), EJSON.stringify(b)

    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
    ,
        modelName: 'Bar'
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
        ,
            modelName: 'Foo'
            selector:
                a: 5
        )
        (
            modelName: 'Foo'
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                a: 6
        ,
            modelName: 'Foo'
            selector:
                a: 5
            fields:
                _: true
        )
        (
            modelName: 'Foo'
            selector:
                a: $in: [5, 6]
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                a: 5
                b: $in: [6, 7]
            fields:
                _: false
                a: true
                c: true
        ,
            modelName: 'Foo'
            selector:
                a: 5
                b: $in: [6, 7]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                a: 5
                b: $in: [6, 7]
            fields:
                _: false
                a: true
                c: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                a: 6
                b: 7
                c: 8
            fields:
                a: true
                d: false
                e: true
        ,
            modelName: 'Foo'
            selector:
                a: 5
                b: 7
                c: 8
            fields:
                _: true
                b: false
                d: false
        )
        (
            modelName: 'Foo'
            selector:
                a: $in: [5, 6]
                b: 7
                c: 8
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            a: 6
            b: 7
            c: 8
    ,
        modelName: 'Foo'
        selector:
            a: 5
            b: 7
            c: 9
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [5, 7]
            fields:
                _: false
                a: false
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 5, 7, 8]
            fields:
                _: false
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            a: 5
            b: 10
    ,
        modelName: 'Foo'
        selector:
            a: 6
            b: $in: [10, 11]
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            'd.x': true
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [5, 7]
        fields:
            _: false
            'd.x': true
            'd.y': true
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            'd.x': true
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [5, 7]
        fields:
            _: false
            d: true
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true

    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
        fields:
            _: false
            a: true
            'd.y': true
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true

        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: -1
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: -1
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            sort:
                d: -1
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: 1
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
            sort:
                d: -1
                a: 1
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
        fields:
            _: false
            a: true
            d: true
        limit: 10
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [3, 4, 5, 6, 7, 8, 10]
            fields:
                _: false
                a: true
                d: true
        )
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
            sort:
                a: 1
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                d: true
            sort:
                a: 1
            limit: 20
        )
        (
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                d: true
            sort:
                a: 1
            limit: 20
        )
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort: # this part isn't covered
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            d: true
        limit: 20
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            d: true
        limit: 5
    )
    testEqual(
        J.fetching.tryQsPairwiseMerge(
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x': true
            limit: 10
        ,
            modelName: 'Foo'
            selector:
                'a.x': $in: [4, 8]
            fields:
                _: false
                a: true
                'd.x.y': true
                'd.x.z': true
            limit: 5
        )
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
    )
    test.isNull J.fetching.tryQsPairwiseMerge(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort:
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x.y': true
            'd.x.z': true
        sort:
            a: -1
        limit: 5
    )


Tinytest.add 'isSelectorCovered', (test, onComplete) ->
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
            a: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
            a: 5
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            $or: [a: 5]
            _id: $in: ["abc", "cde", "def"]
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
    ,
        modelName: 'Foo'
        selector:
            a: 3
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
    ,
        modelName: 'Foo'
        selector:
            a: 3
        modelName: 'Foo'
        selector:
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
        sort:
            a: -1
            b: 1
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
        limit: 100
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
            $or: [c: 6]
        sort:
            b: 1
            a: 1
        limit: 100
    ,
        modelName: 'Foo'
        sort:
            a: -1
            b: 1
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            a: 3
            b: 1
            $or: [c: 6]
    ,
        modelName: 'Foo'
        selector:
            a: 3
            b: 5
    )
    test.isTrue J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
            a: 5
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
            a: $in: [3, 5, 7]
    )
    test.isFalse J.fetching.isSelectorCovered(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort: # sort isn't covered
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            d: true
        limit: 20
    )




Tinytest.add 'isQsCovered', (test, onComplete) ->
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc"]
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["aaa", "abc"]
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
        fields:
            d: true
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "def"]
        fields:
            e: true
    ,
        modelName: 'Foo'
        selector:
            _id: $in: ["abc", "cde", "def"]
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
    ,
        modelName: 'Foo'
        fields:
            a: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            _: false
    ,
        modelName: 'Foo'
        fields:
            a: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            e: false
    ,
        modelName: 'Foo'
        fields:
            d: false
            e: false
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            d: false
    ,
        modelName: 'Foo'
        fields:
            d: false
            e: false
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x': true
    ,
        modelName: 'Foo'
        fields:
            d: true
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x': true
    ,
        modelName: 'Foo'
        fields:
            'd.y': true
            'd.z': true
    )
    test.isTrue J.fetching.isQsCovered(
        modelName: 'Foo'
        fields:
            'd.x.y.z': true
            'd.x.z.a': true
    ,
        modelName: 'Foo'
        fields:
            'd.x.x': true
            'd.x.y': true
            'd.x.z': true
    )
    test.isFalse J.fetching.isQsCovered(
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            'd.x': true
        limit: 10
        sort: # this part isn't covered
            a: 1
    ,
        modelName: 'Foo'
        selector:
            'a.x': $in: [4, 8]
        fields:
            _: false
            a: true
            d: true
        limit: 20
    )


Tinytest.add 'QuerySpec canonicalization', (test) ->
    c = (selector) -> J.fetching._getCanonicalSelector selector
    testEqual = (a, b) ->
        test.equal EJSON.stringify(a), EJSON.stringify(b)

    testEqual c(undefined), undefined
    testEqual c('123x'), _id: '123x'
    testEqual c(_id: 'abc'), _id: 'abc'
    testEqual c(_id: $in: ['abc']), _id: 'abc'
    testEqual c(_id: $in: ['abc', 'def']), _id: $in: ['abc', 'def']
    testEqual c(_id: $in: ['def', 'abc']), _id: $in: ['abc', 'def']
    testEqual c(_id: $in: ['z', 'a', 'Z']), _id: $in: ['Z', 'a', 'z']

    testEqual(
        c(
            b: $in: [6, 4, 3, 10]
            _id: $in: [6, 4, 3, 10]
            a: [6, 4, 3, 10]
        )
        (
            _id: $in: [3, 4, 6, 10]
            a: [6, 4, 3, 10]
            b: $in: [3, 4, 6, 10]
        )
    )

    testEqual(
        c(
            b: [
                c:
                    e: 5
                    d: 6
            ]
            $or: [
                'a.b':
                    e: 5
                    d: 6
            ,
                C:
                    $elemMatch:
                        h: 6
                        g: 5
            ]
        )
        (
            $or: [
                C:
                    $elemMatch:
                        g: 5
                        h: 6
            ,
                'a.b':
                    e: 5
                    d: 6
            ]
            b: [
                c:
                    e: 5
                    d: 6
            ]
        )
    )

    testEqual(
        c(
            b:
                $eq:
                    c: 6
                    b: 5
            a:
                $elemMatch:
                    c: 6
                    b: 5
        )
        (
            a:
                $elemMatch:
                    b: 5
                    c: 6
            b:
                $eq:
                    c: 6
                    b: 5
        )
    )


Tinytest.add 'escapeSubDoc', (test) ->
    d = "a.b":
        c:
            "d*DOT*e*DOT*f.g":
                "h.i.j": "k*DOT*.m.n"
        d: [
            "p"
        ,
            q: "r.s"
        ,
            "t.u**DOT**v": "v.w": "x*DOT*y"
        ]
    d2 = "a*DOT*b":
        c:
            "d**DOT**e**DOT**f*DOT*g":
                "h*DOT*i*DOT*j": "k*DOT*.m.n"
        d: [
            "p"
        ,
            q: "r.s"
        ,
            "t*DOT*u***DOT***v": "v*DOT*w": "x*DOT*y"
        ]

    test.equal J.Model._getEscapedSubdoc(d), d2
    test.equal J.Model._getUnescapedSubdoc(d2), d