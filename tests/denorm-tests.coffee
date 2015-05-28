###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

Tinytest.add "denormalization A -> B", (test) ->
    bar = new $$.Bar
    foo = new $$.Foo
    foo.insert()

    console.log 1
    try
        console.log 'n =', bar.numberOfFoosWithAEqualTo4()
        console.log 2
        foo.a(4)
        foo.save()
        console.log 'n =', bar.numberOfFoosWithAEqualTo4()
        console.log 3
    catch e
        console.error e
