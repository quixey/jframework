###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'CancelButton',
    props:
        onClick:
            type: $$.func

    render: ->
        $$ ('LinkButton'),
            onClick: @prop.onClick()
            $$ ('span'),
                style:
                    fontSize: 12
                    color: '#999'
                ("Cancel")