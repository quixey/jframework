###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


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
                style: _.extend(
                    fontSize: 12
                    @prop.style() ? {}
                )

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