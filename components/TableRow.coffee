###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


J.dc 'TableRow',
    props:
        style:
            type: React.PropTypes.object
            default: {}


    render: ->
        $$ ('table'),
            cellPadding: 0
            cellSpacing: 0
            style: @prop.style()
            $$ ('tbody'),
                {}
                $$ ('tr'),
                    {}
                    (@prop.children())