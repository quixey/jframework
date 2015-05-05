###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'LinkButton',
    props:
        style:
            default: {}
        onClick:
            type: $$.func

    render: ->
        $$ ('span'),
            style:
                _.extend(
                    cursor: 'pointer'
                    color: 'blue'
                ,
                    @prop.style().toObj()
                )
            onClick: (e) => @prop.onClick()? e
            (@prop.children())