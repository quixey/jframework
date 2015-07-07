# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.

if Meteor.isClient
    windowSizeDep = new Tracker.Dependency
    J.getWindowSize = ->
        windowSizeDep.depend()

        size =
            width: window.innerWidth
            height: window.innerHeight

        size

    $(document).ready ->
        $(window).resize -> windowSizeDep.changed()