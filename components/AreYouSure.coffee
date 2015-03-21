J.dc 'AreYouSure',
    props:
        style:
            type: $$.obj
        onClick:
            type: $$.func

    state:
        showingAreYouSure:
            default: false

    render: ->
        if @showingAreYouSure()
            $$ ('div'),
                style: @prop.style() ? {}

                $$ ('span'),
                    style:
                        color: '#999'
                    ("Are you sure?")

                (" ")

                $$ ('LinkButton'),
                    style:
                        fontWeight: 'bold'
                    onClick: (e) =>
                        e.stopPropagation()
                        @prop.onClick()? e

                    ("Yes")

                $$ ('span'),
                    style:
                        color: '#999'

                    (" | ")

                $$ ('LinkButton'),
                    style:
                        color: '#999'
                    onClick: (e) =>
                        e.stopPropagation()
                        @showingAreYouSure false

                    ("No")

        else
            $$ ('div'),
                style: @prop.style() ? {}
                onClick: (e) =>
                    e.stopPropagation()
                    @showingAreYouSure true

                (@prop.children())