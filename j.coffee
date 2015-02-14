J = {}
J.stores = {}


J.debugFlush = true
if J.debugFlush
    trackerFlush = Tracker.flush
    Tracker.flush = ->
        console.debug "Tracker.flush!"
        trackerFlush()


J.bindEnvironment = if Meteor.isServer then Meteor.bindEnvironment else _.identity


J.graph = {} # jid: object
J.debugGraph = true
J._nextId = 0
J.getNextId = ->
    jid = J._nextId
    J._nextId += 1
    jid


if Meteor.isServer
    _collapsed = false
    console.log = ->
        return if _collapsed
        console.log.apply console, arguments
    console.debug = console.log
    console.groupCollapsed = ->
        console.log.apply console, arguments
        _collapsed = true
    console.groupEnd = ->
        _collapsed = false
        console.log.apply console, arguments
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