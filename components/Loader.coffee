# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


J.dc 'Loader',
    props:
        size:
            type: $$.num
            default: 20

    render: ->
        $$ ('img'),
            src: '/images/loader.gif'
            style:
                width: @prop.size()
                height: @prop.size()
                opacity: 0.5
