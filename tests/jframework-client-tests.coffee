# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


Meteor.startup ->
    $("body").css(
        paddingTop: 34
    )

addComponent = (name, component) ->
    divNode = document.createElement 'div'

    componentSection = $("<div>").css(
        border: '1px solid #ccc'
        padding: 20
        marginBottom: 30
    ).append(
        $("<div>").css(
            fontWeight: 'bold'
            paddingBottom: 12
            borderBottom: '1px solid #eee'
            marginBottom: 12
        ).text(name)
        divNode
    )

    element = React.render component, divNode

    setTimeout(
        ->
            $("body").prepend componentSection
        1000
    )

    element


Tinytest.add "Component basics", (test) ->
    lst = J.List [0...5]

    J._defineComponent 'Cp',
        props:
            p:
                type: J.$string
                default: "This is p"

        reactives:
            xPlusOne:
                val: -> @x() + 1

            x:
                type: J.$number
                val: -> lst.get 3

        render: ->
            $$ ("div"),
                {}
                ("Here is p: #{@prop.p()}")

    mountedCp = addComponent 'Component basics', $$ ('Cp'),
        p: "PPP"

    test.equal mountedCp.prop.p(), "PPP"
    test.equal mountedCp.x(), 3
    lst.set(3, 77)
    Tracker.flush()
    test.equal mountedCp.xPlusOne(), 78


Tinytest.add "Component with map", (test) ->
    x = J.Var 5
    a = J.AutoVar 'a', -> x.get()
    b = J.AutoVar 'b', -> a.get()
    c = J.AutoVar 'c', -> b.get()
    c.get()
    x.set 6


    J._defineComponent 'MapTest',
        render: ->
            $$ ('div'),
                {}

                ("Map test")

                $$ ('table'),
                    {}
                    $$ ('tbody'),
                        {}
                        $$ ('tr'),
                            {}
                            $$ ('td'),
                                style:
                                    verticalAlign: 'top'

                                J.List([
                                    'a'
                                    'b'
                                    'c'
                                ]).map (letter) ->
                                    $$ ('div'),
                                        style:
                                            padding: 8
                                            border: '1px solid #ccc'
                                            background: 'lightgreen'
                                            fontWeight: 'bold'
                                        (letter)

                            $$ ('td'),
                                style:
                                    verticalAlign: 'top'
                                    paddingLeft: 20

                                if true
                                    console.log "trying to get c"
                                    null

                                ("Now C is: ")
                                (c.get())

                                if true
                                    console.log "done"
                                    null

    addComponent 'Component with map', $$ ('MapTest')









Tinytest.addAsync "_lastTest", (test, onComplete) ->












