crap = 0

class J.AutoVar
    constructor: (tag, valueFunc, onChange, options) ->
        ###
            AutoVars default to being "lazy", i.e. not calculated
            until .get().

            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoVar becomes non-lazy.

            options:
                creator: Set a different creator computation.
        ###

        unless @ instanceof J.AutoVar
            return new J.AutoVar tag, valueFunc, onChange, options

        if _.isFunction tag
            # Alternate signature: J.AutoVar(valueFunc, onChange, options)
            options = onChange
            onChange = valueFunc
            valueFunc = tag
            tag = undefined

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless not onChange? or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "AutoVar onChange must be either null or a function
                or true (true simply forces non-lazy first evaluation): #{onChange}"

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        @tag = tag
        @valueFunc = valueFunc
        @onChange = onChange ? null
        if options?.creator is undefined
            @creator = Tracker.currentComputation
        else
            @creator = options.creator

        @_var = new J.Var J.Var.NOT_READY,
            creator: @creator
            onChange: if _.isFunction @onChange then @onChange

        @_active = true
        @creator?.onInvalidate =>
            @stop()

        @_valueComp = null
        if @onChange
            # Truthy onChange means do a non-lazy first run
            # of valueFunc.
            Tracker.afterFlush J.bindEnvironment =>
                if @isActive() and not @_valueComp?
                    @_setupValueComp()


    _recompute: ->
        crap += 1
        if crap >= 1000 then crash

        # console.log @tag, @_id, "recomputing..."
        J.assert @_active

        # Pass a @ just like autorun does. This will help in case
        # we ever decide to compute @valueFunc the first time
        # synchronously.
        try
            # ValueFunc may either return or throw J.Var.NOT_READY.
            # It may not return undefined.
            rawValue = @valueFunc.call null, @
        catch e
            throw e unless e is J.Var.NOT_READY
            rawValue = J.Var.NOT_READY

        if rawValue is undefined
            throw new Meteor.Error "#{@toString()}.valueFunc must not return undefined."

        @_var.set rawValue


    _setupValueComp: ->
        console.log "_setupValueComp", @tag, @_id, @_valueComp?, (a.tag for a in @constructor._pending)
        J.assert @isActive()

        @_valueComp?.stop()
        Tracker.nonreactive => Tracker.autorun J.bindEnvironment (c) =>
            if c.firstRun
                # Important to do this here in case @stop() is called during the
                # first run of the computation.
                @_valueComp = c
                @_valueComp.autoVar = @
                @_valueComp.tag = "#{@toString()} valueComp"

            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1

            @_recompute()

            @_valueComp.onInvalidate =>
                console.groupCollapsed "invalidated", @toString()
                console.trace()
                console.groupEnd()
                unless @_valueComp.stopped
                    if @ not in @constructor._pending
                        @constructor._pending.push @


    get: ->
        crap += 1
        if crap >= 1000 then getCrash

        unless @isActive()
            console.error()
            throw new Meteor.Error "#{@constructor.name} ##{@_id} is stopped: #{@}."

        if arguments.length
            throw new Meteor.Error "Can't pass argument to AutoVar.get"

        if Meteor.isServer and J._inMethod.get()
            return @valueFunc.call null, @

        console.log "GET", @tag, @_id, @_valueComp?, (a.tag for a in @constructor._pending)
        if @_valueComp?
            # Note that @ itself may or may not be in @constructor._pending now,
            # and it may also find itself in @constructor._pending during the flush.
            @constructor.flush()
        else
            @_setupValueComp()

        @_var.get()


    isActive: ->
        @_active


    set: ->
        throw new Meteor.Error "There is no AutoVar.set"


    stop: ->
        if @_active
            @_active = false
            @_valueComp?.stop()
            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1


    toString: ->
        s = "AutoVar[#{@_id}](#{J.util.stringifyTag @tag ? ''}=#{J.util.stringify @_var._value})"
        if not @isActive() then s += " (inactive)"
        s


    @_pending: []


    @flush: ->
        console.groupCollapsed("FLUSH called")
        console.log (x.toString() for x in @_pending)
        console.trace()
        console.groupEnd()
        while @_pending.length
            av = @_pending.shift()
            console.debug "FLUSHING ", av.tag, av._id, (a.tag for a in @_pending)
            av._setupValueComp()