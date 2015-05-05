###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'EditButton',
    props:
        onClick:
            type: $$.func

    render: ->
        $$ ('LinkButton'),
            onClick: => @prop.onClick()? {}
            $$ ('img'),
                src: '/images/edit.png'
                style:
                    width: 16
                    height: 16
                    opacity: 0.5