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

    unmountedCp = $$ ('Cp'),
        p: "PPP"
    mountedCp = React.render unmountedCp, document.createElement 'div'

    test.equal mountedCp.prop.p(), "PPP"
    test.equal mountedCp.x(), 3
    lst.set(3, 77)
    test.equal mountedCp.xPlusOne(), 4
    Tracker.flush()
    test.equal mountedCp.xPlusOne(), 78
