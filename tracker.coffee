###
    A few things to augment Meteor's Tracker
###

J._aafQueue = []
J._flushAfterAfQueue = ->
    console.log 'Flush AfterAfQueue'
    while J._aafQueue.length
        func = J._aafQueue.shift()
        func()

_setupAfWaiter = ->
    afIsDone = false
    Tracker.afterFlush -> afIsDone = true
    if afIsDone
        # AfterFlush is now
        J._flushAfterAfQueue()
    else
        # AfterFlush is (synchronously or asynchronously) later
        Tracker.afterFlush -> _setupAfWaiter()


J.afterAf = (f) ->
    ###
        Run f at the soonest possible time after afterFlush
    ###
    J._aafQueue.push f
    if J._aafQueue.length is 1
        setupAfWaiter()


class J.Dependency
    ###
        Like Tracker.Dependency except that a "creator computation",
        i.e. a reactive data source, should be able to freely read
        its own reactive values as it's mutating them without
        invalidating itself.
        But the creator should still invalidate if it reads
        its own values which other objects then mutate.
    ###

    constructor: (@creator = Tracker.currentComputation) ->
        @_dep = new Tracker.Dependency()

    depend: (computation) ->
        @_dep.depend computation

    changed: ->
        if (
            @creator? and Tracker.currentComputation is @creator and
                @creator._id of @_dep._dependentsById
        )
            # The creator computation is changing a dep that it's also
            # watching. So just un-depend and re-depend after this change.
            delete @_dep._dependentsById[@creator._id]
            @_dep.changed()
            @_dep.depend @creator
        else
            @_dep.changed()