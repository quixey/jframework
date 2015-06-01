# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.

J.getWindowSize = ->
    # TODO: Make this a Meteor-style reactive data source
    # by watching the Window size change.

    size =
        width: window.innerWidth
        height: window.innerHeight

    size
