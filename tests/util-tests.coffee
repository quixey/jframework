###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.debugTags = true
J.debugGraph = true

Tinytest.add 'util - sorting', (test) ->
    test.equal J.util.compare(
        [false, -2]
        [1, -5, 6]
    ), -1
    test.equal J.util.compare(
        [1, 2, 3, 'test', 5]
        [1, 2.0, 3, 'TeSt', 5.0]
    ), 0
    test.equal J.assert J.util.compare(
        {key: 6}
        5
    ), 1
    test.isTrue J.util.deepEquals(
        ['G', 'f'].sort(J.util.compare)
        ['f', 'G']
    )

Tinytest.add 'util - matchesUrlPattern', (test) ->
    test.isTrue J.util.matchesUrlPattern(
        "func://yelp.com/search?cflt=restaurants&find_desc=chicken+wings&attrs=GoodForKids&find_loc=Mountain+View%2Cca&sortby=&open_time=",
        "func://yelp.com/search?cflt=restaurants&find_desc=chicken+wings&attrs=GoodForKids&find_loc=Mountain+View%2Cca&sortby=&open_time="
    )
    test.isTrue J.util.matchesUrlPattern(
        'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
        'func://yelp.com/search?q=best+restaurants&loc={mountain+view,ca|}'
    )
    test.isTrue J.util.matchesUrlPattern(
        'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
        'func://yelp.com/search?q=best+restaurants&loc={mountain\+view,ca|}'
    )
    test.isFalse J.util.matchesUrlPattern(
        'func://yelp.com/search?cflt=&q=best+restaurants&loc=mountain+view,CA',
        'func://yelp.com/search?cflt=pizza&q=best+restaurants&loc={mountain+view,ca|}'
    )
    test.isTrue J.util.matchesUrlPattern(
        'func://www.yellowpages.com/friendly-md/chicken-wings-restaurants?&refinements=',
        'func://www.yellowpages.com/friendly-md/chicken-wings-restaurants?&refinements={a||b}'
    )
