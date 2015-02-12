J = {}
J.stores = {}

if Meteor.isServer
    console.groupCollapsed = console.log
    console.groupEnd = console.log
    console.group = console.log

    Meteor.startup ->
        # The point of "init" is to let the client wait
        # until the initial subscription is ready.
        # Stuff that can load in jerky pieces doesn't
        # need to go here.

        # If the server has already defined an "init"
        # publisher, this is a no-op.
        Meteor.publish 'init', ->
            @ready()