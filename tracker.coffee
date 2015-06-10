# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


# A few things to augment Meteor's Tracker.
#
# We monkey patch the tracker package because
# we want other Meteor packages like "mongo"
# to use the same global object.


dummyComputation = Tracker.autorun ->
if dummyComputation._id isnt 1
    # A computation was already created by one of the packages that jframework
    # uses, which means it may be too late for our monkey patch to work right.
    console.warn "JFramework's attempt to monkey patch Tracker might not work."
dummyComputation.stop()

Tracker.active = false

Tracker.currentComputation = null

setCurrentComputation = (c) ->
    Tracker.currentComputation = c
    Tracker.active = c?

_debugFunc = -> Meteor?._debug ? console?.log ? ->

withNoYieldsAllowed = (f) ->
    if not Meteor? or Meteor.isClient then f
    else ->
        args = arguments
        Meteor._noYieldsAllowed -> f.apply null, args

Tracker.pendingComputations = []

# true if a Tracker.flush is scheduled, or if we are in Tracker.flush now
Tracker.willFlush = false

# true if we are in Tracker.flush now
Tracker.inFlush = false

# true if we are computing a computation now, either first time
# or recompute.  This matches Tracker.active unless we are inside
# Tracker.nonreactive, which nullifies currentComputation even though
# an enclosing computation may still be running.
Tracker.inCompute = false

Tracker.afterFlushCallbacks = []

requireFlush = ->
    if not Tracker.willFlush
        setTimeout Tracker.flush, 1
        Tracker.willFlush = true

# Tracker.Computation constructor is visible but private
# (throws an error if you try to call it)
Tracker._constructingComputation = false;

Tracker.Computation = (f, creator) ->
    if not Tracker._constructingComputation
        throw new Error "Tracker.Computation constructor is private;
            use Tracker.autorun"

    Tracker._constructingComputation = false

    @stopped = false
    @invalidated = false

    @_id = J.getNextId()
    if J.debugGraph then J.graph[@_id] = @

    @_onInvalidateCallbacks = []

    @creator = creator
    @_func = f

    @firstRun = true
    @_compute()
    @firstRun = false


Tracker.Computation::onInvalidate = (f) ->
    unless _.isFunction f
        throw new Error "onInvalidate requires a function"

    if Meteor.isServer
        f = Meteor.bindEnvironment f

    if @invalidated
        Tracker.nonreactive =>
            withNoYieldsAllowed(f) @
    else
        @_onInvalidateCallbacks.push f


Tracker.Computation::invalidate = ->
    return if @invalidated

    @invalidated = true

    if not @stopped
        Tracker.pendingComputations.push @

        if Tracker.pendingComputations.length > 1 and (
            @sortKey < Tracker.pendingComputations[Tracker.pendingComputations.length - 2].sortKey
        )
            J.inc 'pcSort'
            Tracker.pendingComputations.sort (a, b) ->
                if a.sortKey < b.sortKey then -1
                else if a.sortKey > b.sortKey then 1
                else 0

        requireFlush()

    # Callbacks can't add callbacks, because
    # self.invalidated is true
    for f in @_onInvalidateCallbacks
        Tracker.nonreactive => withNoYieldsAllowed(f) @

    @_onInvalidateCallbacks = []


Tracker.Computation::stop = ->
    if not @stopped
        @stopped = true
        @invalidate()


Tracker.Computation::_compute = ->
    i = Tracker.pendingComputations.indexOf @
    if i >= 0
        Tracker.pendingComputations.splice i, 1

    @invalidated = false

    previous = Tracker.currentComputation
    setCurrentComputation @
    previousInCompute = Tracker.inCompute
    Tracker.inCompute = true

    try
        withNoYieldsAllowed(@_func) @
    finally
        setCurrentComputation previous
        Tracker.inCompute = previousInCompute


Tracker.Computation::debug = ->
    console.group "Computation[#{@_id}]"
    if @autoVar
        @autoVar.debug()
    else if @component
        @component.debug()
    console.groupEnd()


Tracker.flush = ->
    # console.debug "Tracker.flush!"

    if Tracker.inFlush
        throw new Error "Can't call Tracker.flush while flushing"

    if Tracker.inCompute
        throw new Error "Can't flush inside Tracker.autorun"

    Tracker.inFlush = true
    Tracker.willFlush = true

    while Tracker.pendingComputations.length or Tracker.afterFlushCallbacks.length
        # Recompute all pending computations
        while Tracker.pendingComputations.length
            comp = Tracker.pendingComputations.shift()
            # console.debug 'recompute'
            comp._compute() unless comp.stopped
            J.inc 'recompute'

        if Tracker.afterFlushCallbacks.length
            J.inc 'afterFlush'

            # Call one afterFlush callback, which may
            # invalidate more computations
            afc = Tracker.afterFlushCallbacks.shift()
            # console.debug 'afterFlush', afc
            afc.func.call null

    # console.debug 'flush done'

    Tracker.willFlush = false
    Tracker.inFlush = false


Tracker.autorun = (f, sortKey = 0.5) ->
    if not _.isFunction f
        throw new Error "Tracker.autorun requires a function argument"
    if not _.isNumber sortKey
        throw new Error "Tracker.autorun sortKey must be a number"

    if Meteor.isServer
        f = Meteor.bindEnvironment f

    Tracker._constructingComputation = true
    c = new Tracker.Computation f, Tracker.currentComputation
    c.sortKey = sortKey

    if Tracker.active
        Tracker.onInvalidate -> c.stop()

    c


Tracker.nonreactive = (f) ->
    previous = Tracker.currentComputation
    setCurrentComputation null
    ret = f()
    setCurrentComputation previous
    ret


Tracker.onInvalidate = (f) ->
    if not Tracker.active
        throw new Error "Tracker.onInvalidate requires a currentComputation"

    Tracker.currentComputation.onInvalidate f


Tracker.afterFlush = (f, sortKey = 0.5) ->
    if Meteor.isServer
        f = Meteor.bindEnvironment f

    unless _.isNumber(sortKey)
        throw new Error "afterFlush sortKey must be a number (lower comes first)"

    Tracker.afterFlushCallbacks.push func: f, sortKey: sortKey

    if Tracker.afterFlushCallbacks.length > 1 and (
        sortKey < Tracker.afterFlushCallbacks[Tracker.afterFlushCallbacks.length - 2].sortKey
    )
        Tracker.afterFlushCallbacks.sort (a, b) ->
            if a.sortKey < b.sortKey then -1
            else if a.sortKey > b.sortKey then 1
            else 0

    requireFlush()



class Tracker.Dependency
    # Like Meteor's Tracker.Dependency except that a "creator",
    # i.e. a reactive data source, should be able to freely read
    # its own reactive values as it's mutating them without
    # invalidating itself.
    # But the creator should still invalidate if it reads
    # its own values which other objects then mutate.

    constructor: (creator) ->
        @creator =
            if creator is undefined
                Tracker.currentComputation
            else
                creator

        @_dependents = []


    depend: (computation = Tracker.currentComputation) ->
        return false if not computation?

        if computation in @_dependents
            false
        else
            @_dependents.push computation
            computation.onInvalidate =>
                i = @_dependents.indexOf computation
                @_dependents.splice i, 1
            true


    changed: ->
        for computation in _.clone @_dependents
            unless computation is Tracker.currentComputation is @creator
                computation.invalidate()


    hasDependents: ->
        @_dependents.length > 0
