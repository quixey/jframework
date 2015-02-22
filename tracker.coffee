###
    A few things to augment Meteor's Tracker.

    We monkey patch the tracker package because
    we want other Meteor packages like "mongo"
    to use the same global object.
###



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

pendingComputations = []

# true if a Tracker.flush is scheduled, or if we are in Tracker.flush now
Tracker.willFlush = false

# true if we are in Tracker.flush now
Tracker.inFlush = false

# true if we are computing a computation now, either first time
# or recompute.  This matches Tracker.active unless we are inside
# Tracker.nonreactive, which nullifies currentComputation even though
# an enclosing computation may still be running.
inCompute = false

afterFlushCallbacks = []

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
        pendingComputations.push @

        if pendingComputations.length > 1 and (
            @sortKey < pendingComputations[pendingComputations.length - 1].sortKey
        )
            J.inc 'pcSort'
            pendingComputations.sort (a, b) ->
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
    @invalidated = false

    previous = Tracker.currentComputation
    setCurrentComputation @
    previousInCompute = inCompute
    inCompute = true

    try
        withNoYieldsAllowed(@_func) @
    finally
        setCurrentComputation previous
        inCompute = previousInCompute


Tracker.Computation::debug = ->
    console.group "Computation[#{@_id}]"
    if @autoVar
        @autoVar.debug()
    else if @component
        @component.debug()
    console.groupEnd()


Tracker.flush = (_opts) ->
    # console.debug "Tracker.flush!"

    if Tracker.inFlush
        throw new Error "Can't call Tracker.flush while flushing"

    if inCompute
        throw new Error "Can't flush inside Tracker.autorun"

    Tracker.inFlush = true
    Tracker.willFlush = true

    while pendingComputations.length or afterFlushCallbacks.length
        # Recompute all pending computations
        while pendingComputations.length
            comp = pendingComputations.shift()
            comp._compute() unless comp.stopped
            J.inc 'recompute'

        if afterFlushCallbacks.length
            J.inc 'afterFlush'

            # Call one afterFlush callback, which may
            # invalidate more computations
            afc = afterFlushCallbacks.shift()
            afc.func.call null

    Tracker.willFlush = false
    Tracker.inFlush = false


Tracker.autorun = (f, sortKey = 0.5) ->
    if not _.isFunction f
        throw new Error "Tracker.autorun requires a function argument"
    if not _.isNumber sortKey
        throw new Error "Tracker.autorun sortKey must be a number"

    if Meteor.isServer
        f = Meteor.bindEnvironment f

    @_constructingComputation = true
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

    afterFlushCallbacks.push func: f, sortKey: sortKey

    if afterFlushCallbacks.length > 1 and (
        sortKey < afterFlushCallbacks[afterFlushCallbacks.length - 2].sortKey
    )
        afterFlushCallbacks.sort (a, b) ->
            if a.sortKey < b.sortKey then -1
            else if a.sortKey > b.sortKey then 1
            else 0

    requireFlush()



class Tracker.Dependency
    ###
        Like Meteor's Tracker.Dependency except that a "creator",
        i.e. a reactive data source, should be able to freely read
        its own reactive values as it's mutating them without
        invalidating itself.
        But the creator should still invalidate if it reads
        its own values which other objects then mutate.
    ###

    constructor: (creator) ->
        @creator =
            if creator is undefined
                Tracker.currentComputation
            else
                creator

        @_dependentsById = {}


    depend: (computation) ->
        if not computation?
            return false if not Tracker.active
            computation = Tracker.currentComputation

        id = computation._id
        if id of @_dependentsById
            false
        else
            @_dependentsById[id] = computation
            computation.onInvalidate =>
                delete @_dependentsById[id]
            true


    changed: ->
        for id, computation of @_dependentsById
            unless computation is Tracker.currentComputation is @creator
                @_dependentsById[id].invalidate()


    hasDependents: ->
        not _.isEmpty @_dependentsById
