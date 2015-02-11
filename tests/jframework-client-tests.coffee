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
    test.equal mountedCp.xPlusOne(), 78
    Tracker.flush()
    test.equal mountedCp.xPlusOne(), 78


Tinytest.add "Component with map", (test) ->
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

                                if false
                                    console.log 1
                                    a5 = J.AutoVar(
                                        ->
                                            $$.Foo.fetchOne b: 5
                                        true
                                    )
                                    console.log 2

                                    a6 = J.AutoVar(
                                        ->
                                            $$.Foo.fetchOne b: 6
                                        true
                                    )
                                    console.log 3

                                    ("a5: #{a5.get()}, a6: #{a6.get()}")

                                console.log 4

                                if false
                                    al = J.AutoList(
                                        -> 3
                                        (i) ->
                                            bVal = i + 5
                                            console.log 'al computing', bVal
                                            ret = $$ ('div'),
                                                key: bVal
                                                style:
                                                    background: 'yellow'
                                                    padding: 8
                                                    border: '1px solid #ccc'
                                                    marginBottom: 8
                                                ("A foo with b=#{bVal} is #{$$.Foo.fetchOne(b: bVal)?._id ? "[none]"}")
                                            console.log 6
                                            ret
                                        true
                                    )
                                    console.log 'got al', al
                                    al

                                if true
                                    mapAl = J.List([
                                        5
                                        6
                                        7
                                    ]).map (bVal) ->
                                        $$ ('div'),
                                            style:
                                                background: 'lightBlue'
                                                padding: 8
                                                border: '1px solid #ccc'
                                                marginBottom: 8
                                            ("A foo with b=#{bVal} is #{$$.Foo.fetchOne(b: bVal)?._id ? "[none]"}")

                                    mapAl


    addComponent 'Component with map', $$ ('MapTest')












Tinytest.addAsync "_lastTest", (test, onComplete) ->












